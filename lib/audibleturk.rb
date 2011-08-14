module Audibleturk
  class Config
    require 'yaml'
    @@config_file = "#{Dir.home}/.audibleturk"
    def initialize(params, path=nil)
      @params = params
      @path = path
    end

    def self.file(path=@@config_file)
      file = IO.read(path)
      config = YAML.load(file)
      self.new(config, path)
    end

    def self.main
      @@main ||= self.file
    end

    def self.param
      self.main.param
    end

    def self.save
      @@main or raise "Nothing to save"
      @@main.save
    end


    def self.local
      self.main.local
    end

    def self.app
      self.main.app
    end

    def save
      File.open(@path, 'w') do |out|
        YAML.dump(@params, out)
      end
    end

    def param
      @params
    end

    def local
      File.expand_path(@params['local'])
    end

    def app
      File.expand_path(@params['app'])
    end
  end #Config class

  class Amazon
    require 'rturk'
    @@did_setup = false
    def self.setup
      unless @@did_setup
        aws = Audibleturk::Config.param['aws'] or raise "No AWS credentials in config file"
        RTurk.setup(aws['key'], aws['secret'])
        @@did_setup = true
      end
    end

    class Result
      require 'pstore'
      attr_accessor :transcription, :hit_id
      def initialize(assignment, params)
        params[:url_at] or raise ":url_at param required"
        @hit_id = assignment.hit_id
        @transcription = Audibleturk::Transcription::Chunk.new(assignment.answers.to_hash['transcription']);
        @transcription.url = assignment.answers.to_hash[params[:url_at]]
        @transcription.worker = assignment.worker_id
        @transcription.hit = @hit_id
      end

      def self.all_approved(params)
        params[:url_at] or raise ":url_at param required"
        Audibleturk::Amazon.setup
        results=[]
        i=0
        begin
          i += 1
          new_hits = RTurk.GetReviewableHITs(:page_number => i).hit_ids.collect{|id| RTurk::Hit.new(id) }
          hit_page_results=[]
          new_hits.each do |hit|
            unless hit_results = self.from_cache(hit.id, params[:url_at])
              assignments = hit.assignments
              hit_results = assignments.select{|assignment| (assignment.status == 'Approved') && (assignment.answers.to_hash[params[:url_at]])}.collect{|assignment| self.new(assignment, params)}
              self.to_cache(hit.id, params[:url_at], hit_results) if assignments.select{|assignment| assignment.status == 'Approved' }.length > 0
            end
            hit_page_results.push(hit_results)
          end
          hit_page_results = hit_page_results.flatten
          results.push(*hit_page_results)
        end while new_hits.length > 0 
        results
      end

      def self.from_cache(hit_id, url_at)
        self.cache.transaction { self.cache[self.to_cache_key(hit_id, url_at)] }
      end

      def self.to_cache(hit_id, url_at, results)
        self.cache.transaction { self.cache[self.to_cache_key(hit_id, url_at)] = results }
        results
      end

      def self.to_cache_key(hit_id, url_at)
        "#{hit_id}///#{url_at}"
      end
      def self.cache
        @@cache ||= PStore.new("#{Dir.home}/.audibleturk.cache")
        @@cache
      end
    end #Result class
  end #Amazon class

  class Project
    attr_accessor :name, :config
    def initialize(name, config=Audibleturk::Config.file)
      @name = name
      @config = config
    end

    def www(scp=@config.param['scp'])
      Audibleturk::Project::WWW.new(@name, scp)
    end

    def local(path=nil)
      path ||= @config.local || File.expand_path('Desktop')
      Audibleturk::Project::Local.named(@name, path) or raise "Can't find '#{@name}' in '#{path}'"
    end

    class WWW
      require 'net/sftp'
      attr_accessor :name, :host, :user, :path
      def initialize(name, scp)
        @name = name
        connection = scp.match(/^(.+?)\@(.+?)(\:(.*))?$/) or raise "Could not extract server connection info from scp string '#{scp}'"
        @user = connection[1]
        @host = connection[2]
        @path = connection[4]
        if @path
          @path = @path.sub(/\/$/,'')
          @path = "#{@path}/"
        else
          @path = ''
        end
      end

      def remove(files)
        removals = []
        begin
          Net::SFTP.start(@host, @user) do |sftp|
            files.each do |file|
              removals.push(
                            sftp.remove("#{@path}#{file}")
                            )
            end
            sftp.loop
          end
          failures = removals.reject{|request| request.response.ok? } 
          return {
            :success => failures.empty?,
            :failures => failures,
            :message => failures.empty? ? '' : "File removal error: " + failures.collect{|request| request.response.to_s }.join('; ')
          }
        rescue Net::SSH::AuthenticationFailed
          return {
            :success => false,
            :failures => [],
            :message => "SSH authentication error: #{$!}"
          }
        end
      end
    end #WWW class

    class Local
      attr_reader :path
      def initialize(path)
        @path = path
      end

      def self.named(string, path)
        match = Dir.glob("#{path}/*").select{|entry| File.basename(entry) == string }[0]
        return unless (match && File.directory?(match) && self.ours?(match))
        return self.new(match) 
      end

      def self.ours?(dir)
        (Dir.exists?("#{dir}/audio") && Dir.exists?("#{dir}/originals"))
      end

      def audio_chunks
        Dir.glob("#{@path}/audio/*.mp3").select{|file| not file.match(/\.all\.mp3$/)}.length
      end

      def subtitle
        read('etc/subtitle.txt')
      end

      def subtitle=(subtitle)
        write('etc/subtitle.txt', subtitle)
      end

      def csv(base_name)
        arys = CSV.parse(read("csv/#{base_name}.csv"))
        headers = arys.shift
        arys.collect{|row| Hash[*headers.zip(row).flatten]}
      end

      def read(relative_path)
        path = "#{@path}/#{relative_path}"
        IO.read(path) if File.exists?(path)
      end

      def write(relative_path, data)
        File.open( "#{@path}/#{relative_path}", 'w') do |out|
          out << data
        end
      end
    end #Local class
  end #Project class

  class Transcription
    include Enumerable
    require 'csv'
    attr_accessor :title, :subtitle, :url

    def initialize(title=nil, chunks=[])
      @title = title
      @chunks = chunks
    end

    def each
      @chunks.each do |chunk|
        yield chunk
      end
    end

    def [](index)
      @chunks[index]
    end

    def to_s
      @chunks.join("\n\n")
    end
    
    def self.from_csv(csv_string)
      transcription = self.new
      CSV.parse(csv_string) do |row|
        next if row[16] != 'Approved'                            
        chunk = Audibleturk::Transcription::Chunk.from_csv(row)
        transcription.add_chunk(chunk)
        transcription.title = chunk.title unless transcription.title
      end
      return transcription
    end

    def add_chunk(chunk)
      @chunks.push(chunk)
    end

    class Chunk
      require 'text/format'
      require 'cgi'

      attr_accessor :body, :worker, :title, :hit
      attr_reader :offset_start, :offset_start_seconds, :filename

      def initialize(body)
        @body = body
      end

      def <=>(other)
        self.offset_start_seconds <=> other.offset_start_seconds
      end

      def self.from_csv(row)
        chunk = Chunk.new(row[26])
        chunk.worker = row[15]
        chunk.url = row[25]
        return chunk
      end

      def url=(url)
        #http://ryantate.com/transfer/Speech.01.00.mp3
        #OR, obfuscated: http://ryantate.com/transfer/Speech.01.00.ISEAOMB.mp3
        matches = /.+\/(([\w\/\-]+)\.(\d+)\.(\d\d)(\.\w+)?\.[^\/\.]+)$/.match(url) or raise "Unexpected format to url '#{url}'"
        @url = matches[0]
        @filename = matches[1]
        @title = matches[2] unless @title
        @offset_start = "#{matches[3]}:#{matches[4]}"
        @offset_start_seconds = (matches[3].to_i * 60) + matches[4].to_i
      end

      def url
        @url
      end

      #Remove web filename randomization
      def filename_local
        @filename.sub(/(\.\d\d)\.[A-Z]{6}(\.\w+)$/,'\1\2')
      end

      def wrap_text(text)
        formatter = Text::Format.new
        formatter.first_indent = 0
        formatter.format(text)
      end

      def body_as_html
        text = self.body
        text = CGI::escapeHTML(text)
        text.gsub!("\r\n", "\n")
        text.gsub!("\r", "\n")
        text.gsub!("\f", "\n")
        text.gsub!(/\n\n+/, '<p>')
        text.gsub!("\n", '<br>')
        text.gsub!('<p>', "\n\n<p>")
        text.gsub!('<br>', "\n<br>")
        text.gsub!(/\A\s+/, '')
        text.gsub!(/\s+\z/, '')
        text = text.split("\n").collect {|line| wrap_text(line) }.join("\n") 
        text.gsub!(/\n\n+/, "\n\n")
        text
      end
    end #Chunk subclass
  end #Transcription class
end #Audibleturk module
