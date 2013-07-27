module Typingpool
  #Module encapsulating high-level Typingpool procedures and called
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
  module App
    require 'stringio'
    require 'open3'
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
      #Reads and writes from a Filer::CSV instance passed as the
      #second param, intended to link to a file like
      #Project#local#file('data', 'assignment.csv')
      #
      #Returns an array of urls corresponding to uploaded files. If no
      #files were uploaded, the array will be empty
      # ==== Params
      # [project]          A Project instance.
      # [&block]           Optional. A block that will be called at the
      #                    beginning of each file upload and passed
      #                    the local path to the file and the remote
      #                    name of the file.
      # ==== Returns
      # An array of URLs of the uploaded audio files.
      def upload_audio_for_project(project)
        #we don't make any provision for reading/writing from
        #sandbox-assignment.csv because audio upload data in such files is
        #effectively ignored
        assignments_file = project.local.file('data', 'assignment.csv').as(:csv)
        check_interrupted_uploads(assignments_file, 'audio')
        uploading = assignments_file.reject{|assignment| assignment['audio_uploaded'] == 'yes' }
        return uploading if uploading.empty?
        files = uploading.map{|assignment| Typingpool::Project.local_basename_from_url(assignment['audio_url']) }
        files.map!{|basename| project.local.file('audio', 'chunks', basename).as(:audio) }
        files = Typingpool::Filer::Files.new(files)
        remote_files = with_abort_on_url_mismatch('audio') do
           uploading.map{|assignment| project.remote.url_basename(assignment['audio_url']) }
        end 
        #Record that we're uploading so we'll know later if something
        #goes wrong
        record_assignment_upload_status(assignments_file, uploading, ['audio'], 'maybe')
        project.remote.put(files.to_streams, remote_files) do |file, as|
          yield(file, as) if block_given?
        end
        assignments_files = [assignments_file]
        record_assignment_upload_status(assignments_file, uploading, ['audio'], 'yes')
        uploading.map{|assignment| assignment['audio_url'] }
      end

      #For a subset of a Project instance's chunks/assignments,
      #uploads assignment html that is used as the external question
      #for a Mechanical Turk HIT.
      #
      #Takes the same precautions around interrupted network uploads
      #as upload_audio_for_project.
      #
      #The URL of each uploaded assignment is written into
      #Project#local.file('data', 'assignment.csv'), along with
      #metadata confirming that the upload completed.
      #
      # ==== Params
      # [project]               A Project instance.
      # [assignments_file]      A Filer::CSV instance from which
      #                         assignments_uploading were drawn. The
      #                         upload status will be written and
      #                         tracked here.
      # [assignments_uploading] An enumerable collection of hashes
      #                         corresponding to rows in
      #                         Project#local.file('data',
      #                         'assignment.csv'). Only assignments
      #                         whose URLs are contained in these
      #                         hashes will be uploaded. 
      # [template]              A Template::Assignment instance. Used to render
      #                         assignments_uploading into HTML prior
      #                         to uploading.
      # ==== Returns
      # An array of URLs of the uploaded assignments
      def upload_html_for_project_assignments(project, assignments_file, assignments_uploading, template)
        ios = assignments_uploading.map{|assignment| StringIO.new(template.render(assignment)) }
        remote_basenames = assignments_uploading.map do |assignment| 
          File.basename(project.class.local_basename_from_url(assignment['audio_url']), '.*') + '.html' 
        end 
        remote_names = project.create_remote_names(remote_basenames)
        urls = remote_names.map{|name| project.remote.file_to_url(name) }
        #record upload URLs ahead of time so we can roll back later if the
        #upload fails halfway through
        record_assignment_urls(assignments_file, assignments_uploading, 'assignment', urls)
        record_assignment_upload_status(assignments_file, assignments_uploading, ['assignment'], 'maybe')
        project.remote.put(ios, remote_names)
        record_assignment_upload_status(assignments_file, assignments_uploading, ['assignment'], 'yes')
        urls
      end

      #Removes one or more types of remote files -- audio, assignment
      #html, etc. -- associated with a subset of a Project instance's
      #chunks/assignments.
      #
      #Writes to Project#local.file('data', 'assignment.csv') to
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
      # [assignments_file]       A Filer::CSV instance from which
      #                          assignments_updeleting were
      #                          drawn. The upload status will be
      #                          written and tracked here.
      # [assignments_updeleting] An enumerable collection of hashes
      #                          corresponding to selected rows in
      #                          Project#local#file('data',
      #                          'assignment.csv'). Only assets whose
      #                          URLs are contained in these hashes
      #                          will be deleted.
      #  [types]                 Optional. An array of asset
      #                          'types'. The default, ['audio',
      #                          'assignment'], means assets at
      #                          assignment['audio_url'] and
      #                          assignment['assignment_url'] will be
      #                          deleted for each assignment hash in
      #                          assignments_updeleting and that
      #                          upload status will be tracked in
      #                          assignment['audio_uploaded'] and
      #                          assignment['assignment_uploaded'].
      # [&block]                 Optional. A code block that will be
      #                          called with the name of the remote
      #                          file just before the delete is
      #                          carried out.
      # ==== Returns
      # A count of how many items were actually removed from the
      # server.
      def updelete_assignment_assets(project,  assignments_file, assignments_updeleting=assignments_file, types=['audio', 'assignment'])
        assignments_updeleting = assignments_updeleting.select do |assignment|
          types.select do |type|
            assignment["#{type}_uploaded"] == 'yes' || assignment["#{type}_uploaded"] == 'maybe' 
          end.count > 0
        end.flatten #assignments_updeleting.select...
        urls_updeleting = assignments_updeleting.map do |assignment|
          types.select do |type|
            assignment["#{type}_uploaded"] == 'yes' || assignment["#{type}_uploaded"] == 'maybe'
          end.map{|type| assignment["#{type}_url"] }.select{|url| url }
        end.flatten #assignments_updeleting.map...
        return 0 if urls_updeleting.empty?
        missing = []
        record_assignment_upload_status(assignments_file, assignments_updeleting, types, 'maybe')
        begin
          with_abort_on_url_mismatch do
            project.remote.remove_urls(urls_updeleting){|file| yield(file) if block_given? }
          end
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
        record_assignment_upload_status(assignments_file, assignments_updeleting, types, 'no')
        urls_updeleting.count - missing.count
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
      # An array of hashes of the form {:project => project, :hits
      # =>[hit1,hit2...]}.
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
            project = Typingpool::Project.new(hit.project_title_from_url, config)
            next unless project.local && (project.local.id == hit.project_id)
            next if File.exists? project.local.file(transcript_filename[:done])
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
        by_project_id.keys.sort.map{|key| by_project_id[key] }
      end 

      #Given a Project and assignments file like
      #Project#local#file('data', 'assignments.csv'), writes an HTML
      #transcript for that project within the local project folder
      #(Project#local). To do so, uses data from within Project#local,
      #in particular the data dir and in particular within that the
      #assignment.csv file.
      # ==== Params
      # [project]          A Project instance.
      # [assignments_file] A Filer::CSV instance
      #                    corresponding to a file like
      #                    Project#local#file('data',
      #                    'assignment.csv'). 
      # [config]           Optional. A Config instance. If not supplied, will
      #                    use Project#config. Used to find the
      #                    transcript template (Config#templates is
      #                    examined).
      # ==== Returns
      # Path to the resulting HTML transcript file.
      def create_transcript(project, assignments_file, config=project.config)
        transcript_chunks = assignments_file.select{|assignment| assignment['transcript']}.map do |assignment|
          chunk = Typingpool::Transcript::Chunk.new(assignment['transcript'])
          chunk.url = assignment['audio_url']
          chunk.project = assignment['project_id']
          chunk.worker = assignment['worker']
          chunk.hit = assignment['hit_id']
          chunk
        end #...map do |assignment|
        transcript = Typingpool::Transcript.new(project.name, transcript_chunks)
        transcript.subtitle = project.local.subtitle
        done = (transcript.to_a.length == project.local.subdir('audio', 'chunks').to_a.size)
        out_file = done ? transcript_filename[:done] : transcript_filename[:working]
        begin
          template ||= Template.from_config('transcript', config)
        rescue Error::File::NotExists => e
          abort "Couldn't find the template dir in your config file: #{e}"
        rescue Error => e
          abort "There was a fatal error with the transcript template: #{e}"
        end #begin
        File.delete(project.local.file(transcript_filename[:working])) if File.exists?(project.local.file(transcript_filename[:working]))
        File.open(project.local.file(out_file), 'w') do |out|
          out << template.render({:transcript => transcript})
        end #File.open...
        out_file
      end

      #Creates the file Project#local#file('data',
      #'sandbox-assignments.csv') if it doesn't exist. Populates the
      #file by copying over Project#local#file('data',
      #'assignment.csv') and stripping it of HIT and assignment_url
      #data.
      #
      #Always returns a Filer::CSV instance linked to
      #sandbox-assignmens.csv.
      def ensure_sandbox_assignment_csv(project)
        csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
        return csv if File.exists? csv
        raise Error, "No assignment CSV to copy" unless File.exists? project.local.file('data', 'assignment.csv')
        csv.write(
                  project.local.file('data', 'assignment.csv').as(:csv).map do |assignment|
                    unrecord_hit_in_csv_row(assignment)
                    assignment.delete('assignment_url')
                    assignment.delete('assignment_uploaded')
                    assignment
                  end #project.local.file('data', 'assignment.csv').as(:csv) map...
                  )
        csv
      end

      #Takes Project instance and a boolean indicating whether we're
      #working in the Amazon sandbox. Returns a Filer::CSV instance
      #corresponding to the appropriate assignments file,
      #e.g. Project#local#file('data', 'assignments.csv')#as(:csv).
      def assignments_file_for_sandbox_status(sandbox, project)
        if sandbox
          ensure_sandbox_assignment_csv(project)
        else
          project.local.file('data', 'assignment.csv').as(:csv)
        end
      end

      #Extracts relevant information from a collection of
      #just-assigned Amazon::HITs and writes it into the Project's
      #assignment CSV file for future use.
      # ==== Params
      # [assignments_file] A Filer::CSV instance
      #                    corresponding to a file like
      #                    Project#local#file('data',
      #                    'assignment.csv'). 
      # [hits]            An enumerable collection of Amazon::HIT instances that
      #                   were just assigned (that is, that have one
      #                   assignment, which has a blank status).
      def record_assigned_hits_in_assignments_file(assignments_file, hits)
        record_hits_in_assignments_file(assignments_file, hits) do |hit, csv_row|
          csv_row['hit_id'] = hit.id
          csv_row['hit_expires_at'] = hit.full.expires_at.to_s
          csv_row['hit_assignments_duration'] = hit.full.assignments_duration.to_s
        end #record_hits_in_project do....
      end        

      #Extracts relevant information from a collection of
      #just-approved Amazon::HITs and writes it into the Project's
      #assignment CSV file (Project#local#file('data', 'assignment.csv')) for
      #future use.
      # ==== Params
      # [assignments_file] A Filer::CSV instance
      #                    corresponding to a file like
      #                    Project#local#file('data',
      #                    'assignment.csv'). 
      # [hits]             An enumerable collection of Amazon::HIT instances whose
      #                    one assignment has the status 'Approved'.
      def record_approved_hits_in_assignments_file(assignments_file, hits)
        record_hits_in_assignments_file(assignments_file, hits) do |hit, csv_row|
          next if csv_row['transcript']
          csv_row['transcript'] = hit.transcript.body
          csv_row['worker'] = hit.transcript.worker
          csv_row['hit_id'] = hit.id
        end #record_hits_in_project do...
      end

      #Given a Project instance and an array of modified assignment
      #hashes previously retrieved from the Project's assignment CSV
      #(Project#local#file('data', 'assignment.csv')), writes the
      #'assignment_url' property of each modified hash back to the
      #corresponding row in the original CSV.
#      def record_assignment_urls_in_project(project, assignments)
#        assignments_by_audio_url = Hash[ *assignments.map{|assignment| [assignment['aud#io_url'], assignment] }.flatten ]
#        project.local.file('data', 'assignment.csv').as(:csv).each! do |csv_row|
#          assignment = assignments_by_audio_url[csv_row['audio_url']] or next
#          csv_row['assignment_url'] = assignment['assignment_url']
#        end
#      end

      #Erases all mention of the given Amazon::HITs from one of the
      #Project's assignment CSV files. Typically used when rejecting a
      #HIT assignment.
      # ==== Params
      # [assignments_file] A Filer::CSV instance
      #                    corresponding to a file like
      #                    Project#local#file('data',
      #                    'assignment.csv'). 
      # [hits]              An enumerable collection of Amazon::HIT instances to be
      #                     deleted.
      def unrecord_hits_in_assignments_file(assignments_file, hits)
        record_hits_in_assignments_file(assignments_file, hits) do |hit, csv_row|
          unrecord_hit_in_csv_row(csv_row)
        end
      end

      #Erases particular details of a subset or all of a Project's
      #Amazon::HITs from one of the Project's assignment CSV files.
      #
      #Specifically, deletes information about the HIT's
      #expires_at, and assignments_duration.
      #
      #Typically used when some or all of a Project's HITs have been
      #processed and incorporated into a transcript and are not needed
      #any more as Amazon::HITs on Amazon servers, but when we still
      #want to retain the HIT ids in the Project assignment CSV.
      # ==== Params
      # [assignments_file] A Filer::CSV instance
      #                    corresponding to a file like
      #                    Project#local#file('data',
      #                    'assignment.csv'). 
      # [hits]             Optional. An enumerable collection of Amazon::HIT
      #                    instances whose details are to be
      #                    deleted. If not supplied, details for ALL
      #                    HITs in the Project assignment CSV will be
      #                    deleted.
      def unrecord_hits_details_in_assignments_file(assignments_file, hits=nil)
        record_hits_in_assignments_file(assignments_file, hits) do |hit, csv_row|
          unrecord_hit_details_in_csv_row(csv_row)
        end
      end

      #Checks for Typingpool's external dependencies. If they appear
      #to missing, yields to the passed block an array containing the
      #name of missing commands/packages (e.g. ffmpeg).
      def if_missing_dependencies
        #TODO: Test on Linux
        missing = []
        [['ffmpeg','-version'], ['mp3splt', '-v'], ['mp3wrap']].each do |cmdline|
          begin
            out, err, status = Open3.capture3(*cmdline)
          rescue
            missing.push(cmdline.first)
          end #begin
        end #...].each do |cmdline|
        yield(missing) unless missing.empty?
      end
      #protected

      def with_abort_on_url_mismatch(url_type='')
        url_type += ' '
        begin
          yield
        rescue Typingpool::Error => exception
          if exception.message.match(/not find base url/i)
            abort "Previously recorded #{url_type}URLs don\'t look right. Are you using the right config file? You may have passed in a --config argument to a previous script and forgotten to do so now."
          else
            raise exception
          end
        end #begin
      end

      def record_hits_in_assignments_file(assignments_file, hits)
        hits_by_url = self.hits_by_url(hits) if hits
        assignments_file.each! do |csv_row|
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
            assignment["#{type}_uploaded"] = status if assignment["#{type}_url"]
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
    require 'typingpool/app/friendlyexceptions'
    require 'typingpool/app/cli'
  end #App
end #Typingpool
