module Typingpool
  #Class encapsulating high-level Typingpool procedures and called
  #from the various tp-* scripts. Control layer type code.
  #
  #This is the least mature Typingpool class. At present, all methods
  #are class methods. This will likely change to a model in which
  #different subclasses of App instances do everything from parsing
  #and validating command-line input to completing core functionality
  #to outputing context-dependent result summaries.
  #
  #As such, all App methods should be considered fluid and likely to
  #change in subsequent releases.
  class App
    require 'vcr'
    class << self

      #Extracts relevant information from a collection of
      #just-assigned Amazon::HITs and writes it into the Project's
      #assignment CSV file (Project#local#csv('data', 'assignment.csv')) for
      #future use.
      # ==== Params
      # [project]         A Project instance.
      # [hits]            An enumerable collection of Amazon::HIT instances that
      #                   were just assigned (that is, that have one
      #                   assignment, which has a blank status).
      # [assignment_urls] An array of URLs (strings) corresponding to
      #                   the assignment HTML (Amazon Mechanical Turk
      #                   "external questions") of each of [hits].
      def record_assigned_hits_in_project(project, hits, assignment_urls)
        record_hits_in_project(project, hits) do |hit, csv_row|
          csv_row['hit_id'] = hit.id
          csv_row['hit_expires_at'] = hit.full.expires_at.to_s
          csv_row['hit_assignments_duration'] = hit.full.assignments_duration.to_s
          csv_row['assignment_url'] = assignment_urls.shift
        end #record_hits_in_project do....
      end        

      #Given a collection of Amazon::HITs, looks for Project folders
      #on the local system waiting to "receive" those HITs. Such
      #folders are kept in Config#transcripts. Returns Project
      #instances associated with those folders, bundled together
      #with the related HITs (see below for the exact format of the
      #return value).
      # ==== Params
      # [hits]   An enumerable collection of Amazon::HIT instances.
      # [config] A Config instance.
      # [&block] Optional. A block, if supplied, will be called
      #          repeatedly, each time being passed a different
      #          Project instance and an array of Amazon::HIT
      #          instances, corresponding to the subset of [hits]
      #          belonging to the Project.
      # ==== Returns
      # A hash whose keys are project ids (Project#local#id) and
      # whose values are each a hash of the form {:project =>
      # project, :hits =>[hit1,hit2...]}.
      def find_projects_waiting_for_hits(hits, config)
        need = {}
        by_project_id = {}
        hits.each do |hit| 
          if need[hit.project_id]
            by_project_id[hit.project_id][:hits].push(hit)
          elsif need[hit.project_id] == false
            next
          else
            need[hit.project_id] = false
            project = Typingpool::Project.local_with_id(hit.project_title_from_url, config, hit.transcript.project) or next
            #transcript must not be complete
            next if File.exists?(File.join(project.local.path, transcript_filename[:done]))
            by_project_id[hit.project_id] = {
              :project => project,
              :hits => [hit]
            }
            need[hit.project_id] = true
          end #if need[hit.project_id]
        end #hits.each do...
        if block_given?
          by_project_id.values.each{|hash| yield(hash[:project], hash[:hits]) }
        end
        by_project_id
      end 

      #Extracts relevant information from a collection of
      #just-approved Amazon::HITs and writes it into the Project's
      #assignment CSV file (Project#local#csv('data', 'assignment.csv')) for
      #future use.
      # ==== Params
      # [project] A Project instance.
      # [hits]    An enumerable collection of Amazon::HIT instances whose
      #           one assignment has the status 'Approved'.
      def record_approved_hits_in_project(project, hits)
        record_hits_in_project(project, hits) do |hit, csv_row|
          next if csv_row['transcription']
          csv_row['transcription'] = hit.transcript.body
          csv_row['worker'] = hit.transcript.worker
          csv_row['hit_id'] = hit.id
        end #record_hits_in_project do...
      end

      #Given a Project, writes an HTML transcript for that project
      #within the local project folder (Project#local). To do so, uses
      #data from within Project#local, in particular the data dir and
      #in particular within that the assignment.csv file.
      # ==== Params
      # [project] A Project instance.
      # [config]  Optional. A Config instance. If not supplied, will
      #           use Project#config. Used to find the transcript
      #           template (Config#templates is examined).
      # ==== Returns
      # Path to the resulting HTML transcript file.
      def create_transcript(project, config=project.config)
        transcript_chunks = project.local.csv('data', 'assignment.csv').select{|assignment| assignment['transcription']}.map do |assignment|
          chunk = Typingpool::Transcript::Chunk.new(assignment['transcription'])
          chunk.url = assignment['audio_url']
          chunk.project = assignment['project_id']
          chunk.worker = assignment['worker']
          chunk.hit = assignment['hit_id']
          chunk
        end #...map do |assignment|
        transcript = Typingpool::Transcript.new(project.name, transcript_chunks)
        transcript.subtitle = project.local.subtitle
        File.delete(File.join(project.local.path, transcript_filename[:working])) if File.exists?(File.join(project.local.path, transcript_filename[:working]))
        done = (transcript.to_a.length == project.local.subdir('audio', 'chunks').to_a.size)
        out_file = done ? transcript_filename[:done] : transcript_filename[:working]
        begin
          template ||= Template.from_config('transcript', config)
        rescue Error::File::NotExists => e
          abort "Couldn't find the template dir in your config file: #{e}"
        rescue Error => e
          abort "There was a fatal error with the transcript template: #{e}"
        end #begin
        File.open(File.join(project.local.path, out_file), 'w') do |out|
          out << template.render({:transcript => transcript})
        end #File.open...
        out_file
      end

      #Erases all mention of the given Amazon::HITs from the Project's
      #assignment CSV file (Project#local#csv('data',
      #'assignment.csv')). Typically used when rejecting a HIT
      #assignment.
      # ==== Params
      # [project] A Project instance.
      # [hits]    An enumerable collection of Amazon::HIT instances to be
      #           deleted.
      def unrecord_hits_in_project(project, hits)
        record_hits_in_project(project, hits) do |hit, csv_row|
          unrecord_hit_details_in_csv_row(hit, csv_row)
          csv_row.delete('hit_id')
        end
      end

      #Erases particular details of a subset or all of a Project's
      #Amazon::HITs from the Project's assignment CSV file
      #(Project#local#csv('data', 'assignment.csv')).
      #
      #Specifically, deletes information about the HIT's
      #expires_at, assignments_duration and assignment URL (assignment
      #external question).
      #
      #Typically used when some or all of a Project's HITs have been
      #processed and incorporated into a transcript and are not needed
      #any more as Amazon::HITs on Amazon servers, but when we still
      #want to retain the HIT ids in the Project assignment CSV.
      # ==== Params
      # [project] A Project instance.
      # [hits]    Optional. An enumerable collection of Amazon::HIT
      #           instances whose details are to be deleted. If not
      #           supplied, details for ALL HITs in the Project
      #           assignment CSV will be deleted.
      def unrecord_hits_details_in_project(project, hits=nil)
        record_hits_in_project(project, hits) do |hit, csv_row|
          unrecord_hit_details_in_csv_row(hit, csv_row)
        end
      end

      #Just like unrecord_hits_details_in_project, but does not delete
      #assignment_url information.
      def unrecord_hits_amazon_details_in_project(project, hits=nil)
        record_hits_in_project(project, hits) do |hit, csv_row|
          unrecord_hit_amazon_details_in_csv_row(hit, csv_row)
        end
      end

      #Begins recording of an HTTP mock fixture (for automated
      #testing) using the great VCR gem. Automatically filters your
      #Config#amazon#key and Config#amazon#secret from the recorded
      #fixture, and automatically determines the "cassette" name and
      #"cassette library" dir from the supplied path.
      # ==== Params
      # [fixture_path] Path to where you want the HTTP fixture
      #                recorded, including filename.
      # [config]       A Config instance, used to extract the
      #                Config#amazon#secret and Config#amazon#key that
      #                will be filtered from the fixture.
      # ==== Returns
      # Result of calling VCR.insert_cassette.
      def vcr_record(fixture_path, config)
        VCR.configure do |c|
          c.cassette_library_dir = File.dirname(fixture_path)
          c.hook_into :webmock 
          c.filter_sensitive_data('<AWS_KEY>'){ config.amazon.key }
          c.filter_sensitive_data('<AWS_SECRET>'){ config.amazon.secret }
        end
        VCR.insert_cassette(File.basename(fixture_path, '.*'), :record => :new_episodes)
      end

      #Stops recording of the last call to vcr_record. Returns the
      #result of VCR.eject_cassette.
      def vcr_stop
        VCR.eject_cassette
      end


      #protected

      def record_hits_in_project(project, hits=nil)
        hits_by_url = self.hits_by_url(hits) if hits
        project.local.csv('data', 'assignment.csv').each! do |csv_row|
          if hits
            hit = hits_by_url[csv_row['audio_url']] or next
          end
          yield(hit, csv_row)
        end
      end

      def unrecord_hit_details_in_csv_row(hit, csv_row)
        unrecord_hit_amazon_details_in_csv_row(hit, csv_row)
        csv_row.delete('assignment_url')
      end

      def unrecord_hit_amazon_details_in_csv_row(hit, csv_row)
        %w(hit_expires_at hit_assignments_duration).each{|key| csv_row.delete(key) }
      end



      def transcript_filename
        {
          :done => 'transcript.html',
          :working => 'transcript_in_progress.html'
        }
      end

      def hits_by_url(hits)
        Hash[ *hits.map{|hit| [hit.url, hit] }.flatten ]
      end

    end #class << self
  end #App
end #Typingpool
