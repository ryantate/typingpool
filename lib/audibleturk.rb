module Audibleturk
  class Remote
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
      def initialize(assignment)
        @hit_id = assignment.hit_id
        @transcription = Audibleturk::Transcription::Chunk.new(assignment.answers.to_hash['transcription']);
        @transcription.url = assignment.answers.to_hash['url']
        @transcription.worker = assignment.worker_id
      end

      def self.all_approved
        Audibleturk::Remote.setup
        hits=[]
        i=0
        begin
          i += 1
          new_hits = RTurk.GetReviewableHITs(:page_number => i).hit_ids.inject([]) do |array, hit_id|
            array << RTurk::Hit.new(hit_id); array
          end
          hits.push(*new_hits)
        end while new_hits.length > 0
        results = hits.collect {|hit| self.from_cache(hit.id) || self.to_cache(hit.id, hit.assignments.select{|assignment| (assignment.status == 'Approved') && (assignment.answers.to_hash['url'])}.collect{|assignment| self.new(assignment)})}.flatten
        results
      end

      def self.from_cache(hit_id)
        self.cache.transaction { self.cache[hit_id] }
      end

      def self.to_cache(hit_id, results)
        self.cache.transaction { self.cache[hit_id] = results }
        results
      end

      def self.cache
        @@cache ||= PStore.new("#{Dir.home}/.audibleturk.cache")
        @@cache
      end
    end
  end

  class Folder
    attr_reader :path
    def initialize(path)
      @path = path
    end

    def self.named(string)
      target = Audibleturk::Config.param['local'] || "Desktop"
      target = "#{Dir.home}/#{target}" unless target.match(/^\//)
      match = Dir.glob("#{target}/*").select{|entry| File.basename(entry) == string }[0]
      return unless (match && File.directory?(match) && self.is_ours(match))
      return self.new(match) 
    end

    def self.is_ours(dir)
      (Dir.exists?("#{dir}/audio") && Dir.exists?("#{dir}/originals"))
    end

    def audio_chunks
      Dir.glob("#{@path}/audio/*.mp3").select{|file| not file.match(/\.all\.mp3$/)}.length
    end

    def subtitle
      loc = "#{@path}/etc/subtitle.txt"
      return IO.read(loc) if File.exists?(loc)
      return
    end

    def subtitle=(subtitle)
      File.open("#{@path}/etc/subtitle.txt", 'w') do |out|
        out << subtitle
      end
    end

  end

  class Config
    require 'yaml'
    @@config_file = "#{Dir.home}/.audibleturk"

    def initialize(params, path=nil)
      @params = params
      @path = path
    end

    def self.open(path=@@config_file)
      file = IO.read(path)
      config = YAML.load(file)
      self.new(config, path)
    end

    def self.param
      @@main ||= self.open
      @@main.param
    end

    def self.save
      @@main or raise "Nothing to save"
      @@main.save
    end

    def save
      File.open(@path, 'w') do |out|
        YAML.dump(@params, out)
      end
    end

    def param
      @params
    end

  end

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

      attr_accessor :body, :worker, :title
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
    end
  end
end
