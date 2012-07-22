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

      #Given a Project instance, figures out which audio chunks, if
      #any, need to be uploaded and uploads them.
      #
      #Note that this method is sensitive to the possibility of
      #interrupted batch uploads. It checks for previously interrupted
      #uploads at the start to see if it needs to re-try them, and
      #writes out what uploads it is attempting prior to beginning the
      #upload in case the upload is interrupted by an exception.
      #
      #As such, any script calling this method can usually be simply
      #re-run to re-attempt the upload.
      #
      #Reads and writes from Project#local#csv('data',
      #'assignment.csv') and Project#local#is_audio_on_www.
      #
      #  Returns an array of urls corresponding to uploaded files. If
      #no files were uploaded, the array will be empty
      def upload_audio_for_project(project)
        assignments = project.local.csv('data', 'assignment.csv')
        check_interrupted_uploads(assignments, 'audio')
        uploading = assignments.reject{|assignment| assignment['audio_uploaded'] == 'yes' }
        return uploading if uploading.empty?
        files = uploading.map{|assignment| Typingpool::Project.local_basename_from_url(assignment['audio_url']) }
        files.map!{|basename| project.local.audio('audio', 'chunks', basename) }
        files = Typingpool::Filer::Files.new(files)
        remote_files = uploading.map{|assignment| project.remote.url_basename(assignment['audio_url']) }
        #Record that we're uploading so we'll know later if something
        #goes wrong
        record_assignment_upload_status(assignments, uploading, ['audio'], 'maybe')
        project.remote.put(files.to_streams, remote_files) do |file, as|
          yield(file, as) if block_given?
        end
        record_assignment_upload_status(assignments, uploading, ['audio'], 'yes')
        uploading.map{|assignment| assignment['audio_url'] }
      end

      #Removes one or more types of remote files -- audio, assignment
      #html, etc. -- assoiated with a subset of a Project instance's
      #chunks/assignments.
      #
      #Writes to Project#local.csv('data', 'assignment.csv') to
      #reflect these changes.
      #
      #As with upload_audio_for_project, this method is sensitive to
      #the possibility of interrupted batch operations over the
      #network. This means 
      #  1. It handles deleting files that *might* have been uploaded,
      #  trapping any exceptions that arise if such files do not exist
      #  on the remote server.
      #  2. It writes out what deletions it is attempting before
      #  attempting them, so that if the deletion operation is
      #  interrupted by an exception, the files will be clearly marked
      #  in an unknown state.
      #
      # ==== Params
      # [project]                A Project instance.
      # [assignments_updeleting] An array of hashes corresponding to
      #                          rows in Project#local.csv('data',
      #                          'assignment.csv'). Only assets whose
      #                          URLs are contained in these hashes
      #                          will be deleted.
      # [types]                  Optional. An array of asset 'types'. The default,
      #                          ['audio', 'assignment'], means assets
      #                          at assignment['audio_url'] and
      #                          assignment['assignment_url'] will be
      #                          deleted for each assignment hash in
      #                          assignments_updeleting.
      # ==== Returns
      # A count of how many items were actually removed from the
      # server.
      def updelete_assignment_assets(project, assignments_updeleting, types=['audio', 'assignment'])
        deleting = types.map do |type|
          assignments_updeleting.select do |assignment| 
            assignment["#{type}_uploaded"] == 'yes' || assignment["#{type}_uploaded"] == 'maybe' 
          end.map{|assignment| assignment["#{type}_url"] }
        end.flatten
        return 0 if deleting.empty?
        missing = []
        assignments = project.local.csv('data', 'assignment.csv')
        record_assignment_upload_status(assignments, deleting, types, 'maybe')
        begin
          project.remote.remove_urls(deleting){|file| yield(file) if block_given? }
        rescue Typingpool::Error::File::Remote => exception
          others = []
          exception.message.split('; ').each do |message|
            if message.match(/no such file/i)
              missing.push(message)
            else
              others.push(message)
            end
          end #messages.each...
          raise Error, "Can't remove files: #{others.join('; ')}" if others.count > 0
        end #begin
        record_assignment_upload_status(assignments, deleting, types, 'no')
        deleting.count - missing.count
      end

      #For a subset of a Project instance's chunks/assignments,
      #uploads assignment html that is used as the external question
      #for a Mechanical Turk HIT.
      #
      #Takes the same precautions around interrupted network uploads
      #as upload_audio_for_project.
      #
      #The URL of each uploaded assignment is written into
      #Project#local.csv('data', 'assignment.csv'), along with
      #metadata confirming that the upload completed.
      #
      # ==== Params
      # [project]               A Project instance.
      # [assignments_uploading] An array of hashes corresponding to
      #                         rows in Project#local.csv('data',
      #                         'assignment.csv'). Only assignments
      #                         whose URLs are contained in these
      #                         hashes will be uploaded. This array is
      #                         modified: the field assignment_url is
      #                         added to each hash.
      # [template]              A Template::Assignment instance. Used to render
      #                         assignments_uploading into HTML prior
      #                         to uploading.
      # ==== Returns
      # An array of URLs of the uploaded assignments
      def upload_html_for_project_assignments(project, assignments_uploading, template)
        ios = assignments_uploading.map{|assignment| StringIO.new(template.render(assignment)) }
        remote_basenames = assignments_uploading.map do |assignment| 
          File.basename(project.class.local_basename_from_url(assignment['audio_url']), '.*') + '.html' 
        end 
        remote_names = project.create_remote_names(remote_basenames)
        urls = remote_names.map{|name| project.remote.file_to_url(name) }
        assignments_uploading.each_with_index do |assignment, i|
          assignment['assignment_url'] = urls[i]
        end
        #record upload URLs ahead of time so we can roll back later if the
        #upload fails halfway through
        assignments = project.local.csv('data', 'assignment.csv')
        record_assignment_upload_status(assignments, assignments_uploading, ['assignment'], 'maybe')
        record_assignment_urls(assignments, assignments_uploading, 'assignment', urls)
        project.remote.put(ios, remote_names)
        record_assignment_upload_status(assignments, assignments_uploading, ['assignment'], 'yes')
        assignments_uploading.map{|assignment| assignment['assignment_url'] }
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

      def ensure_sandbox_assignment_csv(project)
        return if File.exists? project.local.csv('data', 'sandbox-assignment.csv')
        raise Error, "No assignment CSV to copy" if not(File.exists? project.local.csv('data', 'assignment.csv'))
        project.local.csv('data', 'sandbox-assignment.csv').write(
                                                                  project.local.csv('data', 'assignment.csv').map do |assignment|
                                                                    unrecord_hit_in_csv_row(assignment)
                                                                    assignment.delete('assignment_url')
                                                                    assignment
                                                                  end #project.local.csv('data', 'assignment.csv') map...
                                                                  )
      end

      #Extracts relevant information from a collection of
      #just-assigned Amazon::HITs and writes it into the Project's
      #assignment CSV file (Project#local#csv('data', 'assignment.csv')) for
      #future use.
      # ==== Params
      # [project]         A Project instance.
      # [hits]            An enumerable collection of Amazon::HIT instances that
      #                   were just assigned (that is, that have one
      #                   assignment, which has a blank status).
      def record_assigned_hits_in_project(project, hits)
        record_hits_in_project(project, hits) do |hit, csv_row|
          csv_row['hit_id'] = hit.id
          csv_row['hit_expires_at'] = hit.full.expires_at.to_s
          csv_row['hit_assignments_duration'] = hit.full.assignments_duration.to_s
        end #record_hits_in_project do....
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

      #Given a Project instance and an array of modified assignment
      #hashes previously retrieved from the Project's assignment CSV
      #(Project#local#csv('data', 'assignment.csv')), writes the
      #'assignment_url' property of each modified hash back to the
      #corresponding row in the original CSV.
#      def record_assignment_urls_in_project(project, assignments)
#        assignments_by_audio_url = Hash[ *assignments.map{|assignment| [assignment['aud#io_url'], assignment] }.flatten ]
#        project.local.csv('data', 'assignment.csv').each! do |csv_row|
#          assignment = assignments_by_audio_url[csv_row['audio_url']] or next
#          csv_row['assignment_url'] = assignment['assignment_url']
#        end
#      end

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
          unrecord_hit_in_csv_row(csv_row)
        end
      end

      #Erases particular details of a subset or all of a Project's
      #Amazon::HITs from the Project's assignment CSV file
      #(Project#local#csv('data', 'assignment.csv')).
      #
      #Specifically, deletes information about the HIT's
      #expires_at, and assignments_duration.
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
          unrecord_hit_details_in_csv_row(csv_row)
        end
      end

      def unrecord_assignment_urls_in_project(project)
        project.local.csv('data', 'assignment.csv').each! do |csv_row|
          csv_row.delete('assignment_url')
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

      def record_hits_in_project(project, hits)
        hits_by_url = self.hits_by_url(hits) if hits
        project.local.csv('data', 'assignment.csv').each! do |csv_row|
          hit = nil
          if hits
            hit = hits_by_url[csv_row['audio_url']] or next
          end
          yield(hit, csv_row)
        end
      end

      def record_assignment_upload_status(assignments, uploading, types, status)
        record_in_selected_assignments(assignments, uploading) do |assignment|
          types.each do |type|
            assignment["#{type}_uploaded"] = status
          end          
        end #record_in_selected_assignments...
      end

      def record_assignment_urls(assignments, uploading, type, urls)
        i = 0
        record_in_selected_assignments(assignments, uploading) do |assignment|
          assignment["#{type}_url"] = urls[i]
          i += 1
        end #record_in_selected_assignments...
      end

      def record_in_selected_assignments(assignments, selected)
        selected_by_url = Hash[ *selected.map{|assignment| [assignment['audio_url'], assignment] }.flatten ]
        assignments.each! do |assignment|
          if selected_by_url[assignment['audio_url']]
            yield(assignment)
          end #if uploading...
        end #assignments.each!...
      end

      def unrecord_hit_details_in_csv_row(csv_row)
        %w(hit_expires_at hit_assignments_duration).each{|key| csv_row.delete(key) }
      end

      def unrecord_hit_in_csv_row(csv_row)
        unrecord_hit_details_in_csv_row(csv_row)
        csv_row.delete('hit_id')
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


      def check_interrupted_uploads(assignments, property)
        assignments.each! do |assignment|
          if assignment["#{property}_uploaded"].to_s == 'maybe'
            assignment["#{property}_uploaded"] = (Typingpool::Utility.working_url? assignment["#{property}_url"]) ? 'yes' : 'no' 
          end
        end #assignments.each!...
      end

    end #class << self
  end #App
end #Typingpool
