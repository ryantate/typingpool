module Typingpool
  require 'typingpool/error'
  require 'typingpool/utility'
  require 'typingpool/config'
  require 'typingpool/filer'

  class Amazon
    require 'rturk'
    require 'pstore'
    @@did_setup = false
    @@cache_file = '~/.typingpool.cache'

    class << self
      def setup(args={})
        @@did_setup = true
        args[:config] ||= Config.file
        args[:key] ||= args[:config].amazon.key
        args[:secret] ||= args[:config].amazon.secret
        args[:sandbox] = false if args[:sandbox].nil?
        if args[:config].cache
          @@cache = nil
          @@cache_file = args[:config].cache
        end
        RTurk.setup(args[:key], args[:secret], :sandbox => args[:sandbox])
      end

      def setup?
        @@did_setup
      end

      def rturk_hit_full(id)
        RTurk::Hit.new(id, nil, :include_assignment_summary => true)
      end

      def cache_file
        File.expand_path(@@cache_file)
      end

      def cache
        @@cache ||= PStore.new(cache_file)
      end

      def to_cache(hash)
        cache.transcation do
          hash.each do |key, value|
            cache[key] = value
          end
        end
      end

      def from_cache(keys)
        values = []
        cache.transaction do
          keys.each do |key|
            values.push(cache[key])
          end
        end
        values
      end
    end #class << self

    class HIT
      require 'set'
      require 'uri'

      class << self
        def create(question, config_assign)
          new(RTurk::Hit.create(:title => config_assign.title || question.title) do |hit|
                hit.description = config_assign.description || question.description
                hit.question(question.url)
                hit.note = question.annotation or raise Error, "Missing annotation from question"
                hit.reward = config_assign.reward or raise Error, "Missing reward config"
                hit.assignments = 1
                hit.lifetime = config_assign.lifetime or raise Error, "Missing lifetime config"
                hit.duration = config_assign.deadline or raise Error, "Missing deadline config"
                hit.auto_approval = config_assign.approval or raise Error, "Missing approval config"
                hit.keywords = config_assign.keywords if config_assign.keywords
                hit.currency = config_assign.currency if config_assign.currency
                config_assign.qualifications.each{|q| hit.qualifications.add(*q.to_arg)} if config_assign.qualifications
              end)
        end

        def id_at
          @@id_at ||= 'typingpool_project_id'
        end

        def url_at
          @@url_at ||= 'typingpool_url'
        end

        def cached_or_new(rturk_hit)
          typingpool_hit=nil
          if typingpool_hit = from_cache(rturk_hit.id)
            puts "DEBUG from_cache"
          else
            typingpool_hit = new(rturk_hit)
            puts "DEBUG from_new"
          end
          typingpool_hit
        end

        def cached_or_new_from_searchhits(rturk_hit, annotation)
          typingpool_hit=nil
          if typingpool_hit = from_cache(rturk_hit.id)
            puts "DEBUG from_cache"
          else
            typingpool_hit = new(rturk_hit)
            typingpool_hit.full(Amazon::HIT::Full::FromSearchHITs.new(rturk_hit, annotation))
            puts "DEBUG from_new"
          end
          typingpool_hit
        end

        def from_cache(hit_id, id_at=self.id_at, url_at=self.url_at)
          Amazon.cache.transaction do
            Amazon.cache[cache_key(hit_id, id_at, url_at)] 
          end
        end

        def delete_cache(hit_id, id_at=self.id_at, url_at=self.url_at)
          Amazon.cache.transaction do
            key = cache_key(hit_id, id_at, url_at)
            cached = Amazon.cache[key]
            Amazon.cache.delete(key) unless cached.nil?
          end
        end

        def cache_key(hit_id, id_at=self.id_at, url_at=self.url_at)
          "RESULT///#{hit_id}///#{url_at}///#{id_at}"
        end

        def with_ids(ids)
          ids.map{|id| cached_or_new(RTurk::Hit.new(id)) }
        end

        def all_approved
          hits = all_reviewable do |hit|
            begin
              #optimization: we assume it is more common to have an
              #unapproved HIT than an approved HIT that does not
              #belong to this app
              hit.approved? && hit.ours? 
            rescue RestClient::ServiceUnavailable => e
              warn "Warning: Service unavailable error, skipped HIT #{hit.id}. (Error: #{e})"
              false
            end
          end
          hits
        end

        def all_reviewable(&filter)
          hits = each_page do |page_number|
            RTurk.GetReviewableHITs(:page_number => page_number).hit_ids.map{|id| RTurk::Hit.new(id) }.map{|hit| cached_or_new(hit) }
          end
          filter_ours(hits, &filter)
        end

        def all_for_project(id)
          all{|hit| hit.ours? && hit.project_id == id}
        end

        def all(&filter)
          hits = each_page do |page_number|
            page = RTurk::SearchHITs.create(:page_number => page_number)
            raw_hits = page.xml.xpath('//HIT')
            page.hits.map do |rturk_hit|
              annotation = raw_hits.shift.xpath('RequesterAnnotation').inner_text.strip
              full = Amazon::HIT::Full::FromSearchHITs.new(rturk_hit, annotation)
              cached_or_new_from_searchhits(rturk_hit, annotation)
            end
          end
          filter_ours(hits, &filter)
        end

        def each_page
          results = []
          page = 0
          begin
            page += 1
            new_results = yield(page)
            results.push(*new_results)
          end while new_results.count > 0
          results
        end

        def filter_ours(hits, &filter)
          filter ||= lambda{|hit| hit.ours? }
          hits.select do |hit| 
            selected = filter.call(hit)
            hit.to_cache
            selected
          end
        end
      end #class << self

      attr_reader :id
      def initialize(rturk_hit)
        @id = rturk_hit.id
      end

      def url
        @url ||= stashed_param(self.class.url_at)
      end

      def project_id
        @project_id ||= stashed_param(self.class.id_at)
      end

      def project_title_from_url(url=self.url)
        matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
        URI.unescape(matches[2])
      end

      def stashed_param(param)
        if @assignment && assignment.answers[param]
          return assignment.answers[param]
        elsif full.annotation[param]
          #A question assigned through this software. May be
          #expensive: May result in HTTP request to fetch HIT
          #fields. We choose to fetch (sometimes) the HIT rather than
          #the assignment on the assumption it will be MORE common to
          #encounter HITs with no answers and LESS common to encounter
          #HITs assigned through the RUI (and thus lacking in an
          #annotation from this software and thus rendering the HTTP
          #request to fetch the HIT fields pointless).
          return full.annotation[param]
        elsif full.assignments_completed.to_i >= 1
          #A question assigned through Amazon's RUI, with an answer
          #submitted. If the HIT belongs to this software, this
          #assignment's answers will include our param.  We prefer
          #fetching the assignment to fetching the external question
          #(as below) because fetching the assignment will potentially
          #save us an HTTP request down the line -- for example, if we
          #need other assignment data (e.g. assignment status).
          #Fetching the external question only serves to give us
          #access to params. If the answers do not include our param,
          #we know the HIT does not belong to this software, since we
          #know the param was also not in the annotation. So we are
          #safe returning nil in that case.
          return assignment.answers[param]
        else
          #A question assigned via Amazon's RUI, with no answer
          #submitted.  Expensive: Results in HTTP request to fetch
          #external question.
          return full.external_question_param(param)
        end
      end

      def approved?
        assignment_status_match?('Approved')
      end

      def rejected?
        assignment_status_match?('Rejected')
      end

      def submitted?
        assignment_status_match?('Submitted')
      end

      def assignment_status_match?(status)
        if @full
          return false if full.assignments_completed == 0
          return false if full.status != 'Reviewable'
        end
        assignment.status == status
      end

      def ours?
        #As in, belonging to this software.
        #One Amazon account can be used for many tasks.
        @ours ||= not(url.to_s.empty?)
      end

      def transcription
        transcript = Transcription::Chunk.new(assignment.body)
        transcript.url = url
        transcript.project = project_id
        transcript.worker = assignment.worker_id
        transcript.hit = @id
        transcript
      end
    alias :transcript :transcription


      def to_cache
        #any obj containing a Nokogiri object cannot be stored in pstore - do
        #not forget this (again)
        if cacheable?
          Amazon.cache.transaction do
            Amazon.cache[self.class.cache_key(@id)] = self 
          end
        end
      end

      @@cacheable_assignment_status = Set.new %w(Approved Rejected)
      def cacheable?
        if @ours == false
          return true
        end
        if @full
          return true if full.expired_and_overdue?
        end
        if @assignment && assignment.status
          return true if @@cacheable_assignment_status.include?(assignment.status)
        end
        return false
      end

      def remove_from_amazon
        if full.status == 'Reviewable'
          if assignment.status == 'Submitted'
            raise Error::Amazon::UnreviewedContent, "There is an unreviewed submission for #{url}"
          end
          at_amazon.dispose!
        else
          at_amazon.disable!
        end
      end

      def at_amazon
        Amazon.rturk_hit_full(@id)
      end
      
      #hit fields segregated because accessing any one of them is
      #expensive if we only have a hit id (but after fetching one all
      #are cheap)
      def full(full_hit=nil)
        if @full.nil?
          @full = full_hit || Full.new(at_amazon)
        end
        @full
      end

      #assignment fields segregated because accessing any one of
      #them is expensive (but after fetching one all are cheap)
      def assignment
        if @assignment.nil?
          if @full && full.assignments_completed == 0
            @assignment = Assignment::Empty.new
          else
            @assignment = Assignment.new(at_amazon) #expensive
          end
        end
        @assignment
      end

      class Full
        require 'uri'
        require 'open-uri'
        require 'nokogiri'
        attr_reader :id, :type_id, :status, :external_question_url, :assignments_completed, :assignments_pending, :expires_at, :assignments_duration
        def initialize(rturk_hit)
          import_standard_attrs_from_rturk_hit(rturk_hit)
          @assignments_completed = rturk_hit.assignments_completed_count
          @assignments_pending = rturk_hit.assignments_pending_count
          self.annotation = rturk_hit.annotation
          self.external_question_url = rturk_hit.xml
        end

        def import_standard_attrs_from_rturk_hit(hit)
          %w(id type_id status expires_at assignments_duration).each do |attr|
            instance_variable_set("@#{attr}", hit.send(attr))
          end
        end

        def annotation=(encoded)
          begin
            @annotation = encoded.to_s
            @annotation = URI.decode_www_form(@annotation) 
            @annotation = Hash[*@annotation.flatten]
          rescue ArgumentError
            #Handle annotations like Department:Transcription (from
            #the Amazon RUI), which make URI.decode_www_form barf
            @annotation = {}
          end
        end

        def annotation
          @annotation ||= {}
        end

        def external_question_url=(noko_xml)
          if question_node = noko_xml.css('HIT Question')[0] #escaped XML
            if url_node = Nokogiri::XML::Document.parse(question_node.inner_text).css('ExternalQuestion ExternalURL')[0]
              @external_question_url = url_node.inner_text
            end
          end
        end

        def external_question
          if @external_question.nil?
            if external_question_url && external_question_url.match(/^http/)
              #expensive, obviously:
              puts "DEBUG fetching external question"
              @external_question = open(external_question_url).read
            end
          end
          @external_question
        end

        def external_question_param(param)
          if external_question
            if input = Nokogiri::HTML::Document.parse(external_question).css("input[name=#{param}]")[0]
              return input['value']
            end
          end
        end

        def expired?
          expires_at < Time.now
        end

        def expired_and_overdue?
          (expires_at + assignments_duration) < Time.now
        end

        class FromSearchHITs < Full
          #RTurk::HITParser objects returned by RTurk::SearchHITs are
          #pointlessly and subtly different from RTurk::GetHITResponse
          #objects. (I need to submit a patch to RTurk.)
          def initialize(rturk_hit, annotation)
            import_standard_attrs_from_rturk_hit(rturk_hit)
            @assignments_completed = rturk_hit.completed_assignments
            @assignments_pending = rturk_hit.pending_assignments
            self.annotation = annotation
          end

          def external_question_url
            unless @checked_question
              self.external_question_url = at_amazon.xml
              @checked_question = true
            end
            @external_question_url
          end

          def at_amazon
            Amazon.rturk_hit_full(@id)
          end
        end #Amazon::HIT::Full::FromSearchHITs
      end #Amazon::HIT::Full

      class Assignment
        attr_reader :id, :status, :worker_id, :submitted_at

        def initialize(rturk_hit)
          if assignment = rturk_hit.assignments[0] #expensive!
            @id = assignment.id
            @status = assignment.status
            @worker_id = assignment.worker_id
            @submitted_at = assignment.submitted_at
            if answers = assignment.answers
              @answers = answers.to_hash
            end
          end
        end

        def answers
          @answers ||= {}
        end

        def body
          (answers['transcription'] || answers['1']).to_s
        end
        
        def at_amazon
          RTurk::Assignment.new(@id)
        end

        class Empty < Assignment
          def initialize
            @answers = {}
          end

        end #Empty
      end #Assignment
    end #HIT

    class Question
      require 'nokogiri'
      require 'uri'
      attr_reader :url, :html

      def initialize(url, html)
        @url = url
        @html = html
      end

      def annotation
        URI.encode_www_form(Hash[*noko.css('input[type="hidden"]').map{|e| [e['name'], e['value']]}.flatten])
      end

      def title
        noko.css('title')[0].content
      end

      def description
        noko.css('#description')[0].content
      end

      def noko(html=@html)
        Nokogiri::HTML(html, nil, 'US-ASCII')
      end
    end #Question
  end #Amazon

  class Project
    require 'stringio'
    attr_reader :interval, :bitrate
    attr_accessor :name, :config
    def initialize(name, config=Config.file)
      @name = name
      @config = config
    end

class << self
    def local(*args)
      project = new(*args)
      if project.local
        return project
      end
    end

    def local_with_id(*args)
      id = args.pop
      if project = local(*args)
        if project.local.id == id
          return project
        end
      end
    end
  end #class << self

    def remote(config=@config)
      Remote.from_config(@name, config)
    end

    def local(dir=@config.transcripts)
      Local.named(@name, dir) 
    end

    def create_local(basedir=@config.transcripts)
      Local.create(@name, basedir, File.join(@config.app, 'templates', 'project'))
    end

    def interval=(mmss)
      formatted = mmss.match(/(\d+)$|((\d+:)?(\d+):(\d\d)(\.(\d+))?)/) or raise Error::Argument::Format, "Interval does not match nnn or [nn:]nn:nn[.nn]"
      @interval = formatted[1] || (formatted[3].to_i * 60 * 60) + (formatted[4].to_i * 60) + formatted[5].to_i + ("0.#{formatted[7].to_i}".to_f)
    end

    def interval_as_min_dot_sec
      #mp3splt uses this format
      "#{(@interval.to_i / 60).floor}.#{@interval % 60}"
    end

    def bitrate=(kbps)
      raise Error::Argument::Format, 'bitrate must be an integer' if kbps.to_i == 0
      @bitrate = kbps
    end

    def create_remote_names(files)
      files.map do |file|
        name = [File.basename(file, '.*'), local.id, pseudo_random_uppercase_string].join('.')
        name += File.extname(file) if not(File.extname(file).to_s.empty?)
        name
      end
    end

    def self.url_regex
      Regexp.new('.+\/((.+)\.(\d+)\.(\d\d)\.[a-fA-F0-9]{32}\.[A-Z]{6}(\.\w+))')
    end

    def self.local_basename_from_url(url)
      matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
      [matches[2..4].join('.'), matches[5]].join
    end

    def pseudo_random_uppercase_string(length=6)
      (0...length).map{(65 + rand(25)).chr}.join
    end

    def create_assignment_csv(relative_path, remote_files, unusual_words=[], voices=[])
      headers = ['audio_url', 'project_id', 'unusual', (1 .. voices.count).map{|n| ["voice#{n}", "voice#{n}title"]}].flatten
      csv = []
      remote_files.each do |file|
        csv << [file, local.id, unusual_words.join(', '), voices.map{|v| [v[:name], v[:description]]}].flatten
      end
      local.csv(*relative_path).write_arrays(csv, headers)
      local.file_path(*relative_path)
    end

    class Remote
      require 'uri'
      attr_accessor :name
      def self.from_config(name, config)
        if config.sftp
          SFTP.new(name, config.sftp)
        elsif config.amazon && config.amazon.bucket
          S3.new(name, config.amazon)
        else
          raise Error, "No valid upload params found in config file (SFTP or Amazon info)"
        end
      end

      def remove_urls(urls)
        basenames = urls.map{|url| url_basename(url) } 
        remove(basenames){|file| yield(file) if block_given? }
      end

      def url_basename(url)
        url.split("#{self.url}/").last or raise Error "Could not find base url '#{self.url}' within longer url #{url}"
      end

      class S3 < Remote
        require 'aws/s3'
        attr_accessor :key, :secret, :bucket
        attr_reader :url
        def initialize(name, amazon_config)
          @name = name
          @config = amazon_config
          @key = @config.key or raise Error::File::Remote::S3, "Missing Amazon key in config"
          @secret = @config.secret or raise Error::File::Remote::S3, "Missing Amazon secret in config"
          @bucket = @config.bucket or raise Error::File::Remote::S3, "Missing Amazon bucket in config"
          @url = @config.url || default_url
        end

        def connect
          AWS::S3::Base.establish_connection!(
                                              :access_key_id => @key,
                                              :secret_access_key => @secret,
                                              :persistent => false,
                                              :use_ssl => true
                                              )
        end

        def disconnect
          AWS::S3::Base.disconnect
        end

        def make_bucket
          AWS::S3::Bucket.create(@bucket)
        end

        def default_url
          "https://#{@bucket}.s3.amazonaws.com"
        end

        def host
          URI.parse(@url).host
        end

        def path
          URI.parse(@url).path
        end

        def batch(io_streams)
          results = []
          io_streams.each_with_index do |stream, i|
            connect if i == 0
            begin
              results.push(yield(stream, i))
            rescue AWS::S3::S3Exception => e
              if e.match(/AWS::S3::SignatureDoesNotMatch/)
                raise Error::File::Remote::S3::Credentials, "S3 operation failed with a signature error. This likely means your AWS key or secret is wrong. Error: #{e}"
              else
                raise Error::File::Remote::S3, "Your S3 operation failed with an Amazon error: #{e}"
              end #if    
            end #begin
          end #files.each
          disconnect unless io_streams.empty?
          results
        end

        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          batch(io_streams) do |stream, i|
            dest = as[i]
            yield(stream, dest) if block_given?
            begin
              AWS::S3::S3Object.store(dest, stream, @bucket,  :access => :public_read)
            rescue AWS::S3::NoSuchBucket
              make_bucket
              retry
            end
            "#{@url}/#{URI.escape(dest)}"
          end #batch
        end

        def remove(files)
          batch(files) do |file, i|
            yield(file) if block_given?
            AWS::S3::S3Object.delete(file, @bucket)
          end
        end
      end #S3

      class SFTP < Remote
        require 'net/sftp'
        attr_reader :host, :user, :path, :url
        def initialize(name, sftp_config)
          @name = name
          @config = sftp_config   
          @user = @config.user or raise Error::File::Remote::SFTP, "No SFTP user specified in config"
          @host = @config.host or raise Error::File::Remote::SFTP, "No SFTP host specified in config"
          @url = @config.url or raise Error::File::Remote::SFTP, "No SFTP url specified in config"
          @path = @config.path || ''
          @path += '/' if @path
        end

        def connection
          begin
            Net::SFTP.start(@host, @user) do |connection|
              yield(connection)
              connection.loop
            end
          rescue Net::SSH::AuthenticationFailed
            raise Error::File::Remote::SFTP, "SFTP authentication failed: #{$?}"
          end
        end

        def batch(files)
          results = []
          connection do |connection|
            files.each do |file|
              results.push(yield(file, connection))
            end
          end
          return results
        end

        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          begin
            i = 0
            batch(io_streams) do |stream, connection|
              dest = as[i]
              i += 1
              yield(stream, dest) if block_given?
              connection.upload(stream, "#{@path}#{dest}")
              file_to_url(dest)
            end
          rescue Net::SFTP::StatusException => e
            raise Error::File::Remote::SFTP, "SFTP upload failed: #{e.description}"
          end
        end

        def file_to_url(file)
          "#{@url}/#{URI.escape(file)}"
        end

        def remove(files)
          requests = batch(files) do |file, connection|
            yield(file) if block_given?
            connection.remove("#{@path}#{file}")
          end
          failures = requests.reject{|request| request.response.ok?}
          if not(failures.empty?)
            summary = failures.map{|request| request.response.to_s}.join('; ')
            raise Error::File::Remote::SFTP, "SFTP removal failed: #{summary}"
          end
        end
      end #SFTP
    end #Remote

    class Local < Filer::Dir
      require 'fileutils'
      require 'securerandom'
      attr_reader :path

      class << self
        def create(name, base_dir, template_dir)
          local = super(File.join(base_dir, name))
          FileUtils.cp_r(File.join(template_dir, '.'), local)
          local.create_id
          local
        end

        def named(string, path)
          match = super
          if match && ours?(match)
            return match
          end
          return
        end

        def ours?(dir)
          File.exists?(dir.subdir('audio')) && File.exists?(dir.subdir('audio', 'originals'))
        end

        def data_file_accessor(*syms)
          syms.each do |sym|
            define_method(sym) do
              file('data',"#{sym.to_s}.txt").read
            end
            define_method("#{sym.to_s}=".to_sym) do |value|
              file('data',"#{sym.to_s}.txt").write(value)
            end
            define_method("delete_#{sym.to_s}".to_sym) do
              if File.exists? file('data',"#{sym.to_s}.txt")
                File.delete(file('data',"#{sym.to_s}.txt"))
              end
            end
          end
        end
      end #class << self

      data_file_accessor :subtitle, :audio_is_on_www

      def id
        file('data','id.txt').read
      end

      def create_id
        if id 
          raise Error, "id already exists" 
        end
        file('data','id.txt').write(SecureRandom.hex(16))
      end
    end #Local
  end #Project

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
    
    def add_chunk(chunk)
      @chunks.push(chunk)
    end

    class Chunk
      require 'cgi'
      require 'text/format'

      attr_accessor :body, :worker, :hit, :project
      attr_reader :offset, :offset_seconds, :filename, :filename_local

      def initialize(body)
        @body = body
      end

      def <=>(other)
        self.offset_seconds <=> other.offset_seconds
      end

      def url=(url)
        #http://ryantate.com/transfer/Speech.01.00.ede9b0f2aed0d35a26cef7160bc9e35e.ISEAOM.mp3
        matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
        @url = matches[0]
        @filename = matches[1]
        @filename_local = Project.local_basename_from_url(@url)
        @offset = "#{matches[3]}:#{matches[4]}"
        @offset_seconds = (matches[3].to_i * 60) + matches[4].to_i
      end

      def url
        @url
      end

      def wrap_text(text)
        formatter = Text::Format.new
        yield(formatter) if block_given?
        formatter.format(text)
      end

      def body_as_text
        text = self.body
        text = Utility.normalize_newlines(text)
        text.gsub!(/\n\n+/, "\n\n")
        text = text.split("\n").map{|line| line.strip }.join("\n")
        if block_given?
          text = text.split("\n\n").map{|line| wrap_text(line){|formatter| yield(formatter) }.chomp }.join("\n\n")
        end
        text
      end

      def body_as_html
        text = body_as_text
        text = CGI::escapeHTML(text)
        text = Utility.newlines_to_html(text)
        text = text.split("\n").map do |line| 
          wrap_text(line){|formatter| formatter.first_indent = 0 }.chomp
        end.join("\n") 
        text
      end
    end #Transcription::Chunk 
  end #Transcription 

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
            project = Typingpool::Project.local_with_id(hit.project_title_from_url, config, hit.transcription.project) or next
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
          csv_row['transcription'] = hit.transcription.body
          csv_row['worker'] = hit.transcription.worker
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
        transcription_chunks = project.local.csv('data', 'assignment.csv').select{|assignment| assignment['transcription']}.map do |assignment|
          chunk = Typingpool::Transcription::Chunk.new(assignment['transcription'])
          chunk.url = assignment['audio_url']
          chunk.project = assignment['project_id']
          chunk.worker = assignment['worker']
          chunk.hit = assignment['hit_id']
          chunk
        end
        transcription = Typingpool::Transcription.new(project.name, transcription_chunks)
        transcription.subtitle = project.local.subtitle
        File.delete(File.join(project.local.path, transcript_filename[:working])) if File.exists?(File.join(project.local.path, transcript_filename[:working]))
        done = (transcription.to_a.length == project.local.subdir('audio', 'chunks').to_a.size)
        out_file = done ? transcript_filename[:done] : transcript_filename[:working]
        begin
          template ||= Template.from_config('transcript', config)
        rescue Error::File::NotExists => e
          abort "Couldn't find the template dir in your config file: #{e}"
        rescue Error => e
          abort "There was a fatal error with the transcript template: #{e}"
        end
        File.open(File.join(project.local.path, out_file), 'w') do |out|
          out << template.render({:transcription => transcription})
        end
        out_file
      end
    end #class << self
  end #App
end #Typingpool
