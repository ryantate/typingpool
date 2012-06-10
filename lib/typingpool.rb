module Typingpool
  require 'typingpool/error'
  require 'typingpool/utility'
  require 'typingpool/config'
  require 'typingpool/filer'
  require 'typingpool/amazon'
  require 'typingpool/project'
  require 'typingpool/transcript'

  class Template
    require 'erb'
    class << self
      def from_config(path, config=Config.file)
        validate_config(config)
        new(path, look_in_from_config(config))
      end

      def look_in_from_config(config)
        look_in =  [File.join(config.app, 'templates'), '']
        look_in.unshift(config.templates) if config.templates
        look_in
      end

      def validate_config(config)
        if config.templates
          File.exists?(config.templates) or raise Error::File::NotExists, "No such templates dir: #{config.templates}"
          File.directory?(config.templates) or raise Error::File::NotExists, "Templates dir not a directory: #{config.templates}"
        end
      end
    end #class << self

    attr_reader :look_in
    def initialize(path, look_in)
      @path = path
      @look_in = look_in
      full_path or raise Error, "Could not find template path '#{path}' in #{look_in.join(',')}"
    end

    def render(hash)
      ERB.new(read, nil, '<>').result(Env.new(hash, self).get_binding)
    end

    def read
      IO.read(full_path)
    end

    def full_path
      look_in.each do |dir|
        extensions.each do |ext| 
          path = File.join(dir, [@path, ext].join)
          if File.exists?(path) && File.file?(path)
            return path
          end
        end
      end
      return
    end

    def extensions
      ['.html.erb', '']
    end

    class Assignment < Template
      def self.look_in_from_config(*args)
        look_in = super(*args)
        look_in.unshift(look_in.reject{|dir| dir.empty? }.map{|dir| File.join(dir, 'assignment') })
        look_in.flatten
      end
    end #Assignment

    class Env
      require 'ostruct'
      def initialize(hash, template)
        @hash = hash
        @template = template
        @ostruct = OpenStruct.new(@hash)
      end

      def get_binding
        binding()
      end

      def read(path)
        @template.class.new(path, localized_look_in).read
      end

      def render(path, hash={})
        @template.class.new(path, localized_look_in).render(@hash.merge(hash))
      end

      def localized_look_in
        look_in = []
        path = @template.full_path
        until @template.look_in.include? path = File.dirname(path)
          look_in.push(path)
        end
        look_in.push(path, (@template.look_in - [path])).flatten
      end

      def method_missing(meth)
        @ostruct.send(meth)
      end
    end #Env
  end #Template

  class App
    require 'vcr'
    class << self
      def vcr_record(fixture_path, config)
        VCR.configure do |c|
          c.cassette_library_dir = File.dirname(fixture_path)
          c.hook_into :webmock 
          c.filter_sensitive_data('<AWS_KEY>'){ config.amazon.key }
          c.filter_sensitive_data('<AWS_SECRET>'){ config.amazon.secret }
        end
        VCR.insert_cassette(File.basename(fixture_path, '.*'), :record => :new_episodes)
      end

      def vcr_stop
        VCR.eject_cassette
      end

      def transcript_filename
        {
          :done => 'transcript.html',
          :working => 'transcript_in_progress.html'
        }
      end

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
          end
        end
        if block_given?
          by_project_id.values.each{|hash| yield(hash[:project], hash[:hits]) }
        end
        by_project_id
      end

      def record_hits_in_project(project, hits=nil)
        hits_by_url = self.hits_by_url(hits) if hits
        project.local.csv('data', 'assignment.csv').each! do |csv_row|
          if hits
            hit = hits_by_url[csv_row['audio_url']] or next
          end
          yield(hit, csv_row)
        end
      end

      def record_approved_hits_in_project(project, hits)
        record_hits_in_project(project, hits) do |hit, csv_row|
          next if csv_row['transcription']
          csv_row['transcription'] = hit.transcript.body
          csv_row['worker'] = hit.transcript.worker
          csv_row['hit_id'] = hit.id
        end
      end

      def record_assigned_hits_in_project(project, hits, assignment_urls)
        record_hits_in_project(project, hits) do |hit, csv_row|
          csv_row['hit_id'] = hit.id
          csv_row['hit_expires_at'] = hit.full.expires_at.to_s
          csv_row['hit_assignments_duration'] = hit.full.assignments_duration.to_s
          csv_row['assignment_url'] = assignment_urls.shift
        end
      end

      def unrecord_hits_details_in_project(project, hits=nil)
        record_hits_in_project(project, hits) do |hit, csv_row|
          unrecord_hit_details_in_csv_row(hit, csv_row)
        end
      end

      def unrecord_hit_details_in_csv_row(hit, csv_row)
        %w(hit_expires_at hit_assignments_duration assignment_url).each{|key| csv_row.delete(key) }

      end

      def unrecord_hits_in_project(project, hits)
        record_hits_in_project(project, hits) do |hit, csv_row|
          unrecord_hit_details_in_csv_row(hit, csv_row)
          csv_row.delete('hit_id')
        end
      end

      def hits_by_url(hits)
        Hash[ *hits.map{|hit| [hit.url, hit] }.flatten ]
      end

      def create_transcript(project, config=project.config)
        transcript_chunks = project.local.csv('data', 'assignment.csv').select{|assignment| assignment['transcription']}.map do |assignment|
          chunk = Typingpool::Transcript::Chunk.new(assignment['transcription'])
          chunk.url = assignment['audio_url']
          chunk.project = assignment['project_id']
          chunk.worker = assignment['worker']
          chunk.hit = assignment['hit_id']
          chunk
        end
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
        end
        File.open(File.join(project.local.path, out_file), 'w') do |out|
          out << template.render({:transcript => transcript})
        end
        out_file
      end
    end #class << self
  end #App
end #Typingpool
