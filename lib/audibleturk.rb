module Audibleturk
  class Error < StandardError 
    class External < Error; end
    class SFTP < Error; end
    class Argument < Error
      class Format < Argument; end
    end
  end

  class Config
    require 'yaml'
    @@config_file = "#{Dir.home}/.audibleturk"
    attr_reader :path

    def initialize(params, path=nil)
      @params = params
      @path = path
    end

    def self.file(path=nil)
      path ||= @@config_file
      self.new(YAML.load(IO.read(path)), path)
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

    def save(path=@path)
      path or raise "No path to save to"
      File.open(path, 'w') do |out|
        YAML.dump(@params, out)
      end
    end

    def param
      @params
    end

    def to_bool(string)
      return if string.nil?
      return if string.to_s.empty?
      %w(false no 0).each{|falsy| return false if string.to_s.downcase.match(/\s*#{falsy}\s*/)}
      return true
    end

    def local
      File.expand_path(@params['local'])
    end

    def app
      File.expand_path(@params['app'])
    end

    def scp
      @params['scp'].sub(/\/$/, '')
    end

    def url
      @params['url'].sub(/\/$/, '')
    end

    def randomize
      to_bool(@params['randomize'])
    end

  end #Config class

  class Amazon
    require 'rturk'
    @@did_setup = false
    def self.setup(aws_key=Audibleturk::Config.param['aws']['key'], aws_secret=Audibleturk::Config.param['aws']['secret'])
      unless @@did_setup
        RTurk.setup(aws_key, aws_secret)
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
    attr_reader :interval, :bitrate
    attr_accessor :name, :config
    def initialize(name, config=Audibleturk::Config.file)
      @name = name
      @config = config
    end

    def www(scp=@config.scp)
      Audibleturk::Project::WWW.new(@name, scp)
    end

    def local(dir=@config.local)
      Audibleturk::Project::Local.named(@name, dir) 
    end

    def create_local(basedir=@config.local)
      Audibleturk::Project::Local.create(@name, basedir, "#{@config.app}/templates/project")
    end

    def interval=(mmss)
      formatted = mmss.match(/(\d+)$|((\d+:)?(\d+):(\d\d)(\.(\d+))?)/) or raise Audibleturk::Error::Argument::Format, "Interval does not match nnn or [nn:]nn:nn[.nn]"
      @interval = formatted[1] || (formatted[3].to_i * 60 * 60) + (formatted[4].to_i * 60) + formatted[5].to_i + ("0.#{formatted[7].to_i}".to_f)
    end

    def interval_as_min_dot_sec
      #mp3splt uses this format
      "#{(@interval.to_i / 60).floor}.#{@interval % 60}"
    end

    def bitrate=(kbps)
      raise Audibleturk::Error::Argument::Format, 'bitrate must be an integer' if kbps.to_i == 0
      @bitrate = kbps
    end

    def convert_audio
      local.original_audio.collect do |path|
        audio = Audio::File.new(path)
        yield(path, bitrate) if block_given?
        File.extname(path).downcase.eql?('.mp3') ? audio : audio.to_mp3(local.tmp_dir, bitrate)
      end
    end

    def merge_audio(files=convert_audio)
      Audio.merge(files, "#{local.final_audio_dir}/#{@name}.all.mp3")
    end

    def split_audio(file)
      file.split(interval_as_min_dot_sec, @name)
    end

    def upload_audio(files=local.audio_chunks, &progress)
     dest = files.collect{|file| File.basename(file.path) + ((@config.randomize == false) ? '' : ".#{psuedo_random_uppercase_string}") + File.extname(file.path)}
      www.put(files.collect{|f| f.path}, dest){|file, as| progress.yield(file, as, www) if progress}
      return dest
    end

    def create_assignment_csv(remote_files, unusual_words=[], voices=[])
      assignment_path = "#{local.path}/csv/assignment.csv"
      CSV.open(assignment_path, 'wb') do |csv|
        csv << ['url', 'unusual', (1 .. voices.size).collect{|n| ["voice#{n}", "voice#{n}title"]}].flatten
        remote_files.each do |file|
          csv << ["#{@config.url}/#{file}", unusual_words.join(', '), voices.collect{|v| [v[:name], v[:description]]}].flatten
        end
      end
      return assignment_path
    end

    def psuedo_random_uppercase_string(length=6)
      (0...length).collect{(65 + rand(25)).chr}.join
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

      def sftp
        begin
          Net::SFTP.start(@host, @user) do |sftp|
            yield(sftp)
            sftp.loop
          end
        rescue Net::SSH::AuthenticationFailed
          raise Audibleturk::Error::SFTP, "SFTP authentication failed: #{$?}"
        end
      end

      def batch(files)
        results = []
        sftp do |sftp|
          files.each do |file|
            results.push(yield(file, sftp))
          end
        end
        return results
      end

      def put(files, as=nil)
        as ||= files.collect{|file| File.basename(file)}
        begin
          i = 0
          batch(files) do |file, sftp|
            dest = as[i]
            i += 1
            yield(file, dest) if block_given?
            sftp.upload(file, "#{@path}/#{dest}")
          end
        rescue Net::SFTP::StatusException => e
          raise Audibleturk::Error::SFTP, "SFTP upload failed: #{e.description}"
        end
      end

      def remove(files)
        requests = batch(files) do |file, sftp|
          sftp.remove("#{@path}#{file}")
        end
        failures = requests.reject{|request| request.response.ok?}
        if not(failures.empty?)
          summary = failures.collect{|request| request.response.to_s}.join('; ')
          raise Audibleturk::Error::SFTP, "SFTP removal failed: #{summary}"
        end
      end
    end #Audibleturk::Project::WWW

    class Local
      require 'fileutils'
      attr_reader :path
      def initialize(path)
        @path = path
      end

      def self.create(name, base_dir, template_dir)
        base_dir.sub!(/\/$/, '')
        template_dir.sub!(/\/$/, '')
        dest = "#{base_dir}/#{name}"
        FileUtils.mkdir(dest)
        FileUtils.cp_r("#{template_dir}/.", dest)
      end

      def self.named(string, path)
        match = Dir.glob("#{path}/*").select{|entry| File.basename(entry) == string }[0]
        return unless (match && File.directory?(match) && self.ours?(match))
        return self.new(match) 
      end

      def self.ours?(dir)
        (Dir.exists?("#{dir}/audio") && Dir.exists?("#{dir}/originals"))
      end

      def tmp_dir
        "#{@path}/etc/tmp"
      end

      def rm_tmp_dir
        FileUtils.rm_r(tmp_dir)
      end

      def original_audio_dir
        "#{@path}/originals"
      end

      def final_audio_dir
        "#{@path}/audio"
      end

      def audio_chunks
        Dir.glob("#{final_audio_dir}/*.mp3").select{|file| not file.match(/\.all\.mp3$/)}.collect{|path| Audio.new(path)}
      end

      def subtitle
        read('etc/subtitle.txt')
      end

      def subtitle=(subtitle)
        write('etc/subtitle.txt', subtitle)
      end

      def original_audio
        Dir.entries(original_audio_dir).select{|entry| File.file?("#{original_audio_dir}/#{entry}") }.reject{|entry| File.extname(entry).downcase.eql?('html')}.collect{|entry| "#{original_audio_dir}/#{entry}"}
      end

      def add_audio(paths, move=false)
        action = move ? 'mv' : 'cp'
        paths.each{|path| FileUtils.send(action, path, original_audio_dir)}
      end

      def csv(base_name)
        csv = read("csv/#{base_name}.csv") or raise "No file #{base_name} in #{@path}/csv"
        arys = CSV.parse(csv)
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

      def finder_open
        system('open', @path)
      end
    end #Audibleturk::Project::Local

    class Audio
      require 'fileutils'
      require 'open3'

      #much like Kernel#system, except it doesn't spew STDERR and
      #STDOUT all over your screen! (when called with multiple args,
      #which with Kernel#systems kills the chance to do shell style
      #stream redirects like 2>/dev/null)
      def self.system_quietly(*cmd)
        exit_status=nil
        err=nil
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thread|
          yield(stdin, stdout, stderr, wait_thread) if block_given?
          err = stderr.gets(nil)
          [stdin, stdout, stderr].each{|stream| stream.send('close')}
          exit_status = wait_thread.value
        end
        if exit_status.to_i > 0
          raise Audibleturk::Error::External, err
        else
          return true
        end
      end

      def self.merge(files, dest)
        if files.size > 1
            Audio.system_quietly('mp3wrap', dest, *files.collect{|file| file.path})
          written = "#{::File.dirname(dest)}/#{::File.basename(dest, '.*')}_MP3WRAP.mp3"
          FileUtils.mv(written, dest)
        else
          FileUtils.cp(files[0].path, dest)
        end
        File.new(dest)
      end

      class File
        attr_reader :path
        def initialize(path)
          raise "No single quotes allowed in file names" if path.match(/'/)
          @path = path
        end

        def to_mp3(dir=::File.dirname(@path), bitrate=nil)
          bitrate ||= self.bitrate || 192
          dest =  "#{dir}/#{::File.basename(@path, '.*')}.mp3"
          Audio.system_quietly('ffmpeg', '-i', @path, '-acodec', 'libmp3lame', '-ab', "#{bitrate}k", '-ac', '2', dest)
          return self.class.new(dest)
        end

        def bitrate
          info = `ffmpeg -i '#{@path}' 2>&1`.match(/(\d+) kb\/s/)
          return info ? info[1] : nil
        end

        def split(interval_in_min_dot_seconds, base_name=::File.basename(@path, '.*'))
          #We have to cd into the wrapfile directory and do everything there because
          #mp3splt is absolutely retarded at handling absolute directory paths
          dir = ::File.dirname(@path)
          Dir.chdir(dir) do
              Audio.system_quietly('mp3splt', '-t', interval_in_min_dot_seconds, '-o', "#{base_name}.@m.@s", ::File.basename(@path)) 
          end
          Dir.entries(dir).select{|entry| ::File.file?("#{dir}/#{entry}")}.reject{|file| file.match(/^\./)}.reject{|file| file.eql?(::File.basename(@path))}.collect{|file| self.class.new("#{dir}/#{file}")}
        end
      end #Audibleturk::Project::Audio::File
    end #Audibleturk::Project::Audio
  end #Audibleturk::Project

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
