module Audibleturk
  class Error < StandardError 
    class Shell < Error; end
    class SFTP < Error; end
    class Argument < Error
      class Format < Argument; end
    end
    class Amazon < Error
      class UnreviewedContent < Amazon; end
    end
  end

  module Utility
    require 'open3'

    #much like Kernel#system, except it doesn't spew STDERR and
    #STDOUT all over your screen! (when called with multiple args,
    #which with Kernel#systems kills the chance to do shell style
    #stream redirects like 2>/dev/null)
    def self.system_quietly(*cmd)
      out, err, status = Open3.capture3(*cmd)
      if status.success?
        return out ? out.chomp : true
      else
        if err
          raise Audibleturk::Error::Shell, err.chomp
        else
          raise Audibleturk::Error::Shell
        end
      end
    end

    def self.timespec_to_seconds(timespec)
      timespec or return
      suffix_to_time = {
        's'=>1,
        'm'=>60,
        'h'=>60*60,
        'd'=>60*60*24,
        'M'=>60*60*24*30,
        'y'=>60*60*24*365
      }
      match = timespec.to_s.match(/^\+?(\d+(\.\d+)?)\s*([#{suffix_to_time.keys.join}])?$/) or raise Audibleturk::Error::Argument::Format, "Can't convert '#{timespec}' to time"
      suffix = match[3] || 's'
      return (match[1].to_f * suffix_to_time[suffix].to_i).to_i
    end

  end #Audibleturk::Utility

  class Config
    require 'yaml'
    @@default_file = File.expand_path("~/.audibleturk")

    def initialize(params)
      @params = params
    end

    def self.default_file
      @@default_file
    end

    def self.file(path=nil)
      path ||= default_file
      self.new(YAML.load(IO.read((path))))
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

    def assignments
      self.assignments = @params['assignments'] || {} if not(@assignments)
      @assignments
    end

    def assignments=(params)
      @assignments = Assignments.new(params)
    end

    class Assignments
      require 'set'
      def initialize(params)
        @params = params
      end

      def param
        @params
      end

      def templates
        File.expand_path(@params['templates']) if @params['templates']
      end

      def qualify
        self.qualify = @params['qualify'] || [] if not(@qualify)
        @qualify
      end

      def qualify=(specs)
        @qualify = specs.collect{|spec| Qualification.new(spec)}
      end

      def add_qualification(spec)
        self.qualify.push(Qualification.new(spec))
      end

      def keywords
        @params['keywords'] ||= []
      end

      def keywords=(array)
        @params['keywords'] = array
      end

      def time_methods
        Set.new(%w(deadline approval lifetime))
      end

      def time_method?(meth)
        time_methods.include?(meth.to_s)
      end

      def equals_method?(meth)
        match = meth.to_s.match(/([^=]+)=$/) or return
        return match[1]
      end

      def method_missing(meth, *args)
        equals_param = equals_method?(meth)
        if equals_param
          args.size == 1 or raise Audibleturk::Error::Argument, "Too many args"
          value = args[0]
          if time_method?(equals_param) && value
            Utility.timespec_to_seconds(value) or raise Audibeturk::Error::Argument::Format, "Can't convert '#{timespec}' to time"
          end
          return param[equals_param] = value
        end
        args.empty? or raise Audibleturk::Error::Argument, "Too many args"
        return Utility.timespec_to_seconds(param[meth.to_s]) if time_method?(meth) && param[meth.to_s]
        return param[meth.to_s]
      end

      class Qualification
        def initialize(spec)
          @raw = spec
          to_arg #make sure value parses
        end

        def to_s
          @raw
        end

        def to_arg
          [type, opts]
        end

        def type
          type = @raw.split(/\s+/)[0].to_sym
          RTurk::Qualification::TYPES[type] or raise Audibleturk::Error::Argument, "Unknown qualification type '#{type.to_s}'"
          type
        end

        def opts
          args = @raw.split(/\s+/)
          if (args.size > 3) || (args.size < 2)
            raise Audibleturk::Error::Argument, "Unexpected number of qualification tokens: #{@raw}"
          end
          args.shift
          comparator(args[0]) or raise Audibleturk::Error::Argument, "Unknown comparator '#{args[0]}' in qualification '#{@raw}'"
          value = 1
          value = args[1] if args.size == 2
          return {comparator(args[0]) => value}
        end

        def comparator(value)
          Hash[
               '>' => :gt,
               '>=' => :gte,
               '<' => :lt,
               '<=' => :lte,
               '==' => :eql,
               '!=' => :not,
               'true' => :eql,
               'exists' => :exists
              ][value]
        end
      end #Config::Assignments::Qualification
    end #Config::Assignments
  end #Config class

  class Amazon
    require 'rturk'
    @@did_setup = false
    @@cache_file = '~/.audibleturk.cache'

    def self.setup(args={})
      @@did_setup = true
      args[:config] ||= Audibleturk::Config.file
      args[:key] ||= args[:config].param['aws']['key']
      args[:secret] ||= args[:config].param['aws']['secret']
      args[:sandbox] = false if args[:sandbox].nil?
      if args[:config].param['cache']
        @@cache = nil
        @@cache_file = args[:config].param['cache']
      end
      RTurk.setup(args[:key], args[:secret], :sandbox => args[:sandbox])
    end

    def self.setup?
      @@did_setup
    end

    def self.cache_file
      File.expand_path(@@cache_file)
    end

    def self.cache
      @@cache ||= PStore.new(cache_file)
    end

    def self.to_cache(hash)
      self.cache.transcation do
        hash.each do |key, value|
          self.cache[key] = value
        end
      end
    end

    def self.from_cache(keys)
      values = []
      self.cache.transaction do
        keys.each do |key|
          values.push(self.cache[key])
        end
      end
      values
    end

    class Assignment
      require 'nokogiri'
      require 'uri'

      def initialize(htmlf, config_assignment)
        @htmlf = htmlf
        @config = config_assignment
      end

      def assign
        HIT.create(:title => title) do |hit|
          hit.description = description
          hit.reward = @config.reward or raise Audibleturk::Error, "Missing reward config"
          hit.assignments = @config.copies or raise Audibleturk::Error, "Missing copies config"
          hit.question(question)
          hit.lifetime = @config.lifetime or raise Audibleturk::Error, "Missing lifetime config"
          hit.duration = @config.deadline or raise Audibleturk::Error, "Missing deadline config"
          hit.auto_approval = @config.approval or raise Audibleturk::Error, "Missing approval config"
          hit.keywords = @config.keywords if @config.keywords
          hit.currency = @config.currency if @config.currency
          @config.qualifications.each{|q| hit.qualifications.add(*q.to_arg)} if @config.qualifications
          hit.note = annotation if annotation
        end
      end

      def title
        noko.css('#title')[0].content
      end

      def description
        noko.css('#description')[0].content
      end

      def question
        Hash[
         :id => 1, 
         :overview => to_allowed_xhtml(noko.css('#overview')[0].inner_html),
         :question => to_allowed_xhtml(noko.css('#question')[0].inner_html)
        ]
      end

      def annotation
          URI.encode_www_form(Hash[*noko.css('input[type="hidden"]').collect{|e| [e['name'], e['value']]}.flatten])
      end

      def to_allowed_xhtml(htmlf)
        h = noko(htmlf)
        %w(id class style).each do |attribute| 
          h.css("[#{attribute}]").each do |element|
            element.remove_attribute(attribute)
          end
        end
        %w(input div span).each do |name| 
          h.css(name).each{|e| e.remove}
        end
        h.css('body').inner_html
      end

      def noko(html=@htmlf)
        Nokogiri::HTML(html, nil, 'US-ASCII')
      end
    end #Amazon::Assignment


    class Result
      require 'pstore'
      require 'nokogiri'
      require 'set'

      def self.cached_or_new(hit, params)
        #        self.from_cache(hit.id, params[:id_at], params[:url_at]) || self.new(hit, params)
        r=nil
        if r = self.from_cache(hit.id, params[:id_at], params[:url_at])
          puts "DEBUG from_cache"
        else
          r = self.new(hit, params)
puts "DEBUG from_new"
        end
        r
      end

      def self.from_cache(hit_id, id_at, url_at)
        Amazon.cache.transaction do
          Amazon.cache[self.cache_key(hit_id, id_at, url_at)] 
        end
      end

      def self.delete_cache(hit_id, id_at, url_at)
        Amazon.cache.transaction do
          cached = Amazon.cache[self.cache_key(hit_id, id_at, url_at)]
          cached.delete unless cached.nil?
        end
      end

      def self.cache_key(hit_id, id_at, url_at)
        "RESULT///#{hit_id}///#{url_at}///#{id_at}"
      end

      def self.all_approved(params)
        results=[]
        i=0
        begin
          i += 1
          page_results = RTurk.GetReviewableHITs(:page_number => i).hit_ids.collect{|id| RTurk::Hit.new(id) }.collect{|hit| self.cached_or_new(hit, params) }
          filtered_results = page_results.select do |result| 
            begin
              result.approved? && result.ours? 
            rescue RestClient::ServiceUnavailable => e
              warn "Warning: Service unavailable error, skipped HIT #{result.hit_id}. (Error: #{e})"
              false
            end
          end 
          page_results.each{|result| result.to_cache }
          results.push(*filtered_results)
        end while page_results.length > 0 
        results
      end

      def self.all_for_project(id, params)
        results = all(params)
        filtered = results.select{|result| result.ours? && result.project_id == id}
        results.each{|result| result.to_cache}
        filtered
      end

      def self.all_for_hit_type_id(id, params)
        results = all(params)
        filtered = results.select{|result| result.hit.type_id == id}
        results.each{|result| result.to_cache}
        filtered
      end

      def self.all(params)
        params[:full_hit] = true
        results = []
        i = 0
        begin
          i += 1
          page = RTurk::SearchHITs.create(:page_number => i)
          raw_hits = page.xml.xpath('//HIT')
          page_results=[]
          page.hits.each_with_index do |hit, i|
            #We have to jump through hoops because SearchHITs stupidly
            #throws away annotation data (unlike GetHIT) and also
            #renames some fields
            annotation = raw_hits[i].xpath('RequesterAnnotation').inner_text.strip
            wrapped_hit = Amazon::HIT::FromSearchHITs.new(hit, annotation, raw_hits[i])
            result = self.cached_or_new(wrapped_hit, params)
            result.to_cache
            page_results.push(result)
          end
          #          page_results = RTurk::SearchHITs.create(:page_number => i).hits.collect{|hit| RTurk::Hit.new(hit.id, hit) }.collect{|hit| self.cached_or_new(hit, params) }
          #          page_results.each{|result| result.to_cache}
          results.push(*page_results)
        end while page_results.length > 0
        results
      end

      attr_reader :url_at, :id_at, :hit_id
      def initialize(hit, params)
        @url_at = params[:url_at] or raise ":url_at param required"
        @id_at = params[:id_at] or raise ":id_at param required"
        @hit_id = hit.id
        self.hit(hit) if params[:full_hit]
      end

      def url
        @url ||= stashed_param(@url_at)
      end

      def project_id
        @project_id ||= stashed_param(@id_at)
      end

      def stashed_param(param)
        if @from_assignment && assignment.answers[param]
          return assignment.answers[param]
        elsif hit.annotation[param]
          #A question assigned through this software. May be
          #expensive: May result in HTTP request to fetch HIT
          #fields. We choose to fetch (sometimes) the HIT rather than
          #the assignment on the assumption it will be MORE common to
          #encounter HITs with no answers and LESS common to encounter
          #HITs assigned through the RUI (and thus lacking in an
          #annotation from this software and thus rendering the HTTP
          #request to fetch the HIT fields pointless).
          return hit.annotation[param]
        elsif hit.assignments_completed.to_i >= 1
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
          return hit.external_question_param(param)
        end
      end

      def approved?
        assignment_status_match?('Approved')
      end

      def rejected?
        assignment_status_match?('Rejected')
      end

      def assignment_status_match?(status)
        if @from_hit
          return false if hit.assignments_completed == 0
          return false if hit.status != 'Reviewable'
        end
        assignment.status == status
      end

      def ours?
        #As in, belonging to this software.
        #One Amazon account can be used for many tasks.
        @ours ||= not(url.to_s.empty?)
      end

      def transcription
        transcript = Audibleturk::Transcription::Chunk.new(assignment.body)
        transcript.url = url
        transcript.project = project_id
        transcript.worker = assignment.worker_id
        transcript.hit = hit_id
        transcript
      end

      def to_cache
        #any obj containing a Nokogiri object cannot be stored in pstore - do
        #not forget this (again)
        if cacheable?
          Amazon.cache.transaction do
            Amazon.cache[self.class.cache_key(@hit_id, @id_at, @url_at)] = self 
          end
        end
      end

      @@cacheable_assignment_status = Set.new %w(Approved Rejected)
      def cacheable?
        if @ours == false
          return true
        end
        if @from_hit
          return true if hit.expired_and_overdue?
        end
        if @from_assignment && assignment.status
          return true if @@cacheable_assignment_status.include?(assignment.status)
        end
        return false
      end

      def remove_hit
        if hit.status == 'Reviewable'
          if assignment.status == 'Submitted'
            raise Audibleturk::Error::Amazon::UnreviewedContent, "There is an unreviewed submission for #{url}"
          end
          hit_at_amazon.dispose!
        else
          hit_at_amazon.disable!
        end
      end

      def hit_at_amazon
        Amazon::HIT.new_full(@hit_id)
      end
      
      #hit fields segregated because accessing any one of them is
      #expensive if we only have a hit id (but after fetching one all
      #are cheap)
      def hit(hit=nil)
        if @from_hit.nil?
          if hit
            #If the hit was supplied, it was from SearchHIT and lacks a question element
            @from_hit = Fields::FromHIT::WithoutQuestion.new(hit)
          else
            @from_hit = Fields::FromHIT.new(hit_at_amazon)
          end
        end
        @from_hit
      end

      #assignment fields segregated because accessing any one of
      #them is expensive (but after fetching one all are cheap)
      def assignment
        if @from_assignment.nil?
          if @from_hit && hit.assignments_completed == 0
            @from_assignment = Fields::FromAssignment::Empty.new
          else
            @from_assignment = Fields::FromAssignment.new(hit_at_amazon) #expensive
          end
        end
        @from_assignment
      end

      class Fields
        class FromHIT
          require 'uri'
          require 'open-uri'
          require 'nokogiri'
          attr_reader :type_id, :status, :external_question_url, :assignments_completed, :assignments_pending, :expires_at, :assignments_duration
          def initialize(hit)
            @id = hit.id
            @type_id = hit.type_id
            @status = hit.status
            @expires_at = hit.expires_at
            @assignments_duration = hit.assignments_duration
            @assignments_completed = hit.assignments_completed_count
            @assignments_pending = hit.assignments_pending_count
            self.annotation = hit
            self.external_question_url = hit.xml
          end

          def annotation=(hit)
            begin
              @annotation = hit.annotation  || ''
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

          class WithoutQuestion < FromHIT
            def external_question_url
              unless @checked_question
puts "DEBUG re-fetching HIT to get question"
                self.external_question_url = at_amazon.xml
                @checked_question = true
              end
              @external_question_url
            end

            def at_amazon
              Amazon::HIT.new_full(@id)
            end
          end #Amazon::Result::Fields::FromHIT::WithoutQuestion
        end #Amazon::Result::Fields::FromHIT

        class FromAssignment
          attr_reader :status, :worker_id

          def initialize(hit)
            if assignment = hit.assignments[0] #expensive!
              @status = assignment.status
              @worker_id = assignment.worker_id
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
          
          class Empty < FromAssignment
            def initialize
              @answers = {}
            end

          end #Amazon::Result::Fields::FromAssignment::Empty
        end #Amazon::Result::Fields::FromAssignment
      end #Amazon::Result::Fields
    end #Amazon::Result

    class HIT
      #Extend RTurk to handle external questions (see
      #Audibleturk::CreateHIT and Audibleturk::Amazon::HIT::Question
      #class below)
      def self.create(*args, &blk)
        response = CreateHIT.create(*args, &blk)
        RTurk::Hit.new(response.hit_id, response)
      end

      #Convenience method for new RTurk HITs that do what you want
      def self.new_full(id)
        RTurk::Hit.new(id, nil, :include_assignment_summary => true)
      end

      class FromSearchHITs
        #Wrap RTurk::HITParser objects returned by RTurk::SearchHITs, which are pointlessly and stupidly and
        #subtly different from RTurk::GetHITResponse objects
        attr_reader :annotation, :xml
        def initialize(rturk_hit, annotation, noko_xml)
          @rturk_hit = rturk_hit
          @annotation = annotation
          @xml = noko_xml
        end

        def method_missing(meth, *args)
          @rturk_hit.send(meth, *args)
        end

        def assignments_pending_count
          self.pending_assignments
        end

        def assignments_available_count
          self.available_assignments
        end

        def assignments_completed_count
          self.completed_assignments
        end

      end #Amazon::HIT::FromSearchHITs

        class Question
          require 'nokogiri'
        def initialize(args)
          @id = args[:id] or raise Audibleturk::Error::Argument, 'missing :id arg'
          @question = args[:question] or raise Audibleturk::Error::Argument, 'missing :question arg'
          @title = args[:title]
          @overview = args[:overview]
        end

        def to_params
          Nokogiri::XML::Builder.new do |xml|
            xml.root{
              xml.QuestionForm(:xmlns => 'http://mechanicalturk.amazonaws.com/AWSMechanicalTurkDataSchemas/2005-10-01/QuestionForm.xsd'){
                xml.Overview{
                  xml.Title @title if @title
                  if @overview
                    xml.FormattedContent{
                      xml.cdata @overview
                    }
                  end
                }  
                xml.Question{
                  xml.QuestionIdentifier @id
                  xml.IsRequired 'true'
                  xml.QuestionContent{
                    xml.FormattedContent{
                      xml.cdata @question
                    }
                  }
                  xml.AnswerSpecification{
                    xml.FreeTextAnswer()
                  }
                }
              }
            }
          end.doc.root.children.collect{|c| c.to_xml}.join
        end
      end #Amazon::HIT::Question
    end #Amazon::HIT
  end #Amazon

  #RTurk only handles external questions, so we do some subclassing
  class CreateHIT < RTurk::CreateHIT
    def question(*args)
      if args.empty?
        @question
      else
        @question ||= Amazon::HIT::Question.new(*args)
      end
    end
  end #CreateHIT

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

    def upload_audio(files=local.audio_chunks, as=audio_chunks_for_online(files, @config.randomize), &progress)
      www.put(files, as){|file, as| progress.yield(file, as, www) if progress}
      local.audio_is_on_www = as.collect{|file| "#{@config.url}/#{file}"}.join("\n")
      return as
    end

      def audio_chunks_for_online(files=local.audio_chunks, randomize=@config.randomize)
        files.collect{|file| File.basename(file, '.*') + ((randomize == false) ? '' : ".#{psuedo_random_uppercase_string}") + File.extname(file) }
      end

    def updelete_audio(files=local.audio_chunks_online, &progress)
      www.remove(files){|file| progress.yield(file) if progress}
      local.delete_audio_is_on_www
    end

    def create_assignment_csv(remote_files, unusual_words=[], voices=[])
      assignment_path = "#{local.path}/csv/assignment.csv"
      CSV.open(assignment_path, 'wb') do |csv|
        csv << ['url', 'project_id', 'unusual', (1 .. voices.size).collect{|n| ["voice#{n}", "voice#{n}title"]}].flatten
        remote_files.each do |file|
          csv << ["#{@config.url}/#{file}", local.id, unusual_words.join(', '), voices.collect{|v| [v[:name], v[:description]]}].flatten
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
          yield(file) if block_given?
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
      require 'securerandom'
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
        local = self.new(dest)
        local.create_id
        local
      end

      def self.named(string, path)
        match = Dir.glob("#{path}/*").select{|entry| File.basename(entry) == string }[0]
        return unless (match && File.directory?(match) && self.ours?(match))
        return self.new(match) 
      end

      def self.ours?(dir)
        (Dir.exists?("#{dir}/audio") && Dir.exists?("#{dir}/originals"))
      end


      def self.etc_file_accessor(*syms)
        syms.each do |sym|
          define_method(sym) do
            read_file(File.join('etc',"#{sym.to_s}.txt"))
          end
          define_method("#{sym.to_s}=".to_sym) do |value|
            write_file(File.join('etc',"#{sym.to_s}.txt"), value)
          end
          define_method("delete_#{sym.to_s}".to_sym) do
            delete_file(File.join('etc',"#{sym.to_s}.txt"))
          end
        end
      end

      etc_file_accessor :subtitle, :amazon_hit_type_id, :audio_is_on_www

      def tmp_dir
        File.join(path, 'etc', 'tmp')
      end

      def rm_tmp_dir
        FileUtils.rm_r(tmp_dir)
      end

      def original_audio_dir
        File.join(path, 'originals')
      end

      def final_audio_dir
        File.join(path, 'audio')
      end

      def audio_chunks
        Dir.glob("#{final_audio_dir}/*.mp3").reject{|file| file.match(/\.all\.mp3$/)}.map{|path| Audio::File.new(path)}
      end


      def audio_chunks_online
        audio_urls.map{|url| File.basename(URI.parse(url).path)}
      end

      def audio_urls
        read_csv('assignment').map{|row_hash| row_hash['url'] }
      end

       def id
         read_file(File.join('etc','id.txt'))
       end

      def create_id
        if id 
          raise Audibleturk::Error, "id already exists" 
        end
        write_file(File.join('etc','id.txt'), SecureRandom.hex(16))
      end

      def original_audio
        Dir.entries(original_audio_dir).select{|entry| File.file?(File.join(original_audio_dir, entry)) }.reject{|entry| File.extname(entry).downcase.eql?('html')}.reject{|entry| entry.match(/^\./) }.map{|entry| File.join(original_audio_dir, entry) }
      end

      def add_audio(paths, move=false)
        action = move ? 'mv' : 'cp'
        paths.each{|path| FileUtils.send(action, path, original_audio_dir)}
      end

      def read_csv(base_name)
        csv = read_file("csv/#{base_name}.csv") or raise "No file #{base_name} in #{@path}/csv"
        arys = CSV.parse(csv)
        headers = arys.shift
        arys.collect{|row| Hash[*headers.zip(row).flatten]}
      end

      def write_csv(base_name, hashes, headers=hashes[0].keys)
        CSV.open("#{@path}/csv/#{base_name}.csv", 'wb') do |csv|
          csv << headers
          hashes.each{|hash| csv << headers.collect{|header| hash[header] } }
        end
      end

      def read_file(relative_path)
        path = "#{@path}/#{relative_path}"
        if File.exists?(path)
          return IO.read(path)
        else
          return nil
        end
      end

      def write_file(relative_path, data)
        File.open( "#{@path}/#{relative_path}", 'w') do |out|
          out << data
        end
      end

      def delete_file(relative_path)
        path = "#{@path}/#{relative_path}"
        if File.exists?(path)
          File.delete(path)
        else
          return nil
        end
      end

      def finder_open
        system('open', @path)
      end
    end #Audibleturk::Project::Local

    class Audio
      require 'fileutils'

      def self.merge(files, dest)
        raise Audibleturk::Error::Argument, "No files to merge" if files.empty?
        if files.size > 1
          Utility.system_quietly('mp3wrap', dest, *files.collect{|file| file.path})
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

        def to_s
          @path
        end

        def to_str
          to_s
        end

        def to_mp3(dir=::File.dirname(@path), bitrate=nil)
          bitrate ||= self.bitrate || 192
          dest =  "#{dir}/#{::File.basename(@path, '.*')}.mp3"
          Utility.system_quietly('ffmpeg', '-i', @path, '-acodec', 'libmp3lame', '-ab', "#{bitrate}k", '-ac', '2', dest)
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
            Utility.system_quietly('mp3splt', '-t', interval_in_min_dot_seconds, '-o', "#{base_name}.@m.@s", ::File.basename(@path)) 
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

      attr_accessor :body, :worker, :title, :hit, :project
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
        matches = /.+\/(([\w\/\-]+)\.(\d+)\.(\d\d)(\.\w+)?\.[^\/\.]+)/.match(url) or raise "Unexpected format to url '#{url}'"
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
    end #Transcription::Chunk 
  end #Transcription 
  require 'ostruct'
  class ErbBinding < OpenStruct
    def get_binding
      binding()
    end
  end #ErbBinding
end #Audibleturk module
