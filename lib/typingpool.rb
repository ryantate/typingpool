module Typingpool
  class Error < StandardError 
    class Shell < Error; end
    class Argument < Error
      class Format < Argument; end
    end
    class File < Error
      class NotExists < File; end
      class Remote < File
        class SFTP < Remote; end
        class S3 < Remote
          class Credentials < S3; end
        end #S3
      end #Remote
    end #File
    class Amazon < Error
      class UnreviewedContent < Amazon; end
    end #Amazon
  end #Error

  module Utility
    require 'open3'
    class << self
      #much like Kernel#system, except it doesn't spew STDERR and
      #STDOUT all over your screen! (when called with multiple args,
      #which with Kernel#systems kills the chance to do shell style
      #stream redirects like 2>/dev/null)
      def system_quietly(*cmd)
        out, err, status = Open3.capture3(*cmd)
        if status.success?
          return out ? out.chomp : true
        else
          if err
            raise Error::Shell, err.chomp
          else
            raise Error::Shell
          end
        end
      end

      def timespec_to_seconds(timespec)
        timespec or return
        suffix_to_time = {
          's'=>1,
          'm'=>60,
          'h'=>60*60,
          'd'=>60*60*24,
          'M'=>60*60*24*30,
          'y'=>60*60*24*365
        }
        match = timespec.to_s.match(/^\+?(\d+(\.\d+)?)\s*([#{suffix_to_time.keys.join}])?$/) or raise Error::Argument::Format, "Can't convert '#{timespec}' to time"
        suffix = match[3] || 's'
        return (match[1].to_f * suffix_to_time[suffix].to_i).to_i
      end

      def array_to_hash(array, headers)
        Hash[*headers.zip(array).flatten] 
      end

    end #class << self
  end #Utility

  class Config
    require 'yaml'
    @@default_file = "~/.audibleturk"

    def initialize(params)
      @param = params
    end

    class << self
      def default_file
        @@default_file
      end

      def file(path=File.expand_path(default_file))
        Root.new(YAML.load(IO.read((path))))
      end

      def define_reader(*syms)
        syms.each do |sym|
          define_method(sym) do
            value = @param[sym.to_s]
            yield(value)
          end
        end
      end

      def define_writer(*syms)
        syms.each do |sym|
          define_method("#{sym.to_s}=".to_sym) do |value|
            @param[sym.to_s] = yield(value)
          end
        end
      end

      def local_path_reader(*syms)
        define_reader(*syms) do |value|
          File.expand_path(value) if value
        end
      end

      def never_ends_in_slash_reader(*syms)
        define_reader(*syms) do |value|
          value.sub(/\/$/, '') if value
        end
      end

      def time_accessor(*syms)
        define_reader(*syms) do |value|
          Utility.timespec_to_seconds(value) if value
        end
        define_writer(*syms) do |value|
          Utility.timespec_to_seconds(value) or raise Error::Argument::Format, "Can't convert '#{value}' to time"
          value
        end
      end

      def inherited(subklass)
        @@subklasses ||= {}
        @@subklasses[subklass.name.downcase] = subklass
      end

      def subklass?(param)
        @@subklasses["#{self.name.downcase}::#{param.downcase}"] 
      end
    end #class << self

    def to_hash
      @param
    end

    def [](key)
      @param[key]
    end

    def []=(key, value)
      @param[key] = value
    end

    def method_missing(meth, *args)
      equals_param = equals_method?(meth)
      if equals_param
        args.size == 1 or raise Error::Argument, "Wrong number of args(#{args.size} for 1)"
        return @param[equals_param] = args[0]
      end
      args.empty? or raise Error::Argument, "Too many args #{meth} #{args.join('|')}"
      value = @param[meth.to_s]
      if self.class.subklass?(meth.to_s) && value
        return self.class.subklass?(meth.to_s).new(value)
      end
      value
    end

    def equals_method?(meth)
      match = meth.to_s.match(/([^=]+)=$/) or return
      return match[1]
    end

    class Root < Config
      local_path_reader :transcripts, :app, :cache, :templates

      class SFTP < Config
        never_ends_in_slash_reader :path, :url
      end

      class Amazon < Config
        never_ends_in_slash_reader :url
      end

      class Assign < Config
        local_path_reader :templates
        time_accessor :deadline, :approval, :lifetime

        def qualify
          self.qualify = @param['qualify'] || [] if not(@qualify)
          @qualify
        end

        def qualify=(specs)
          @qualify = specs.map{|spec| Qualification.new(spec)}
        end

        def add_qualification(spec)
          self.qualify.push(Qualification.new(spec))
        end

        def keywords
          @param['keywords'] ||= []
        end

        def keywords=(array)
          @param['keywords'] = array
        end

        class Qualification < Config
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
            RTurk::Qualification::TYPES[type] or raise Error::Argument, "Unknown qualification type '#{type.to_s}'"
            type
          end

          def opts
            args = @raw.split(/\s+/)
            if (args.size > 3) || (args.size < 2)
              raise Error::Argument, "Unexpected number of qualification tokens: #{@raw}"
            end
            args.shift
            comparator(args[0]) or raise Error::Argument, "Unknown comparator '#{args[0]}' in qualification '#{@raw}'"
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
        end #Qualification
      end #Assign
    end #Root
  end #Config

  class Amazon
    require 'rturk'
    require 'pstore'
    @@did_setup = false
    @@cache_file = '~/.audibleturk.cache'

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
          hit.reward = @config.reward or raise Error, "Missing reward config"
          hit.assignments = @config.copies or raise Error, "Missing copies config"
          hit.question(question)
          hit.lifetime = @config.lifetime or raise Error, "Missing lifetime config"
          hit.duration = @config.deadline or raise Error, "Missing deadline config"
          hit.auto_approval = @config.approval or raise Error, "Missing approval config"
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
        URI.encode_www_form(Hash[*noko.css('input[type="hidden"]').map{|e| [e['name'], e['value']]}.flatten])
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

        def cached_or_new(hit, is_full_hit=false)
          r=nil
          if r = from_cache(hit.id)
            puts "DEBUG from_cache"
          else
            r = new(hit, is_full_hit)
            puts "DEBUG from_new"
          end
          r
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

        def all_approved
          results=[]
          i=0
          begin
            i += 1
            page_results = RTurk.GetReviewableHITs(:page_number => i).hit_ids.map{|id| RTurk::Hit.new(id) }.map{|hit| cached_or_new(hit) }
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

        def all_for_project(id)
          results = all
          filtered = results.select{|result| result.ours? && result.project_id == id}
          results.each{|result| result.to_cache}
          filtered
        end

        def all
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
              result = cached_or_new(wrapped_hit, true)
              result.to_cache
              page_results.push(result)
            end
            results.push(*page_results)
          end while page_results.length > 0
          results
        end
      end #class << self

      attr_reader :hit_id
      def initialize(hit, is_full_hit=false)
        @hit_id = hit.id
        self.hit(hit) if is_full_hit
      end

      def id
        @hit_id
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
        transcript = Transcription::Chunk.new(assignment.body)
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
            Amazon.cache[self.class.cache_key(@hit_id)] = self 
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
            raise Error::Amazon::UnreviewedContent, "There is an unreviewed submission for #{url}"
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
      alias :full :hit

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

          end #Empty
        end #FromAssignment
      end #Fields
    end #Result

    class HIT
      class << self
        #Extend RTurk to handle external questions (see
        #CreateHIT and Amazon::HIT::Question
        #class below)
        def create(*args, &blk)
          response = CreateHIT.create(*args, &blk)
          RTurk::Hit.new(response.hit_id, response)
        end

        #Convenience method for new RTurk HITs that do what you want
        def new_full(id)
          RTurk::Hit.new(id, nil, :include_assignment_summary => true)
        end
      end #class << self
      class FromSearchHITs
        #Wrap RTurk::HITParser objects returned by RTurk::SearchHITs,
        #which are pointlessly and stupidly and subtly different from
        #RTurk::GetHITResponse objects
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

      end #FromSearchHITs

      class Question
        require 'nokogiri'
        def initialize(args)
          @id = args[:id] or raise Error::Argument, 'missing :id arg'
          @question = args[:question] or raise Error::Argument, 'missing :question arg'
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
          end.doc.root.children.map{|c| c.to_xml}.join
        end
      end #Question
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
    require 'stringio'

    attr_reader :interval, :bitrate
    attr_accessor :name, :config
    def initialize(name, config=Config.file)
      @name = name
      @config = config
    end

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

    def convert_audio
      local.original_audio.map do |path|
        audio = Audio::File.new(path)
        yield(path, bitrate) if block_given?
        File.extname(path).downcase.eql?('.mp3') ? audio : audio.to_mp3(local.tmp_dir, bitrate)
      end
    end

    def merge_audio(files=convert_audio)
      Audio.merge(files, File.join(local.path, 'audio', "#{@name}.all.mp3"))
    end

    def split_audio(file)
      file.split(interval_as_min_dot_sec, @name)
    end

    def upload_audio(files=local.audio_chunks, as=create_audio_remote_names(files), &progress)
      urls = remote.put(files.map{|file| File.new(file.to_s) }, as){|file, as| progress.yield(file, as, remote) if progress}
      local.audio_is_on_www = urls.join("\n")
      urls
    end

    def create_audio_remote_names(files=local.audio_chunks)
      create_remote_file_basenames(files).map{|name| [name, '.mp3'].join }
    end

    def updelete_audio(files=local.audio_remote_names, &progress)
      remote.remove(files)
      local.delete_audio_is_on_www
    end

    def upload_assignments(template, assignments=local.csv('csv/assignment.csv').read, as=create_assignment_remote_names(assignments))
      urls = remote.put(assignments.map{|assignment| StringIO.new(template.render(assignment)) }, as) do |file, as|
        yield(file, as, remote) if block_given?
      end
      urls
    end

    def updelete_assignments(assignments=local.csv('csv/assignment.csv').read)
      remote.remove(local.assignment_remote_names(assignments))
    end

    def create_assignment_remote_names(assignments)
      audio_files = assignments.map{|assignment| assignment['audio_url']}.map{|url| Project.local_basename_from_url(url) }
      create_remote_file_basenames(audio_files).map{|name| [name, '.html'].join }
    end

    def create_remote_file_basenames(from=local.audio_chunks)
      from.map do |file|
        [File.basename(file, '.*'), local.id, pseudo_random_uppercase_string].join('.')
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

    def create_assignment_csv(remote_files, unusual_words=[], voices=[])
      headers = ['audio_url', 'project_id', 'unusual', (1 .. voices.size).map{|n| ["voice#{n}", "voice#{n}title"]}].flatten
      csv = []
      remote_files.each do |file|
        csv << [file, local.id, unusual_words.join(', '), voices.map{|v| [v[:name], v[:description]]}].flatten
      end
      local.csv('csv', 'assignment.csv').write_arrays!(csv, headers)
      local.file_path('csv', 'assignment.csv')
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

      class S3 < Remote
        require 'aws/s3'
        attr_accessor :key, :secret, :bucket
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

    class Local
      require 'fileutils'
      require 'securerandom'
      attr_reader :path
      def initialize(path)
        @path = path
      end

      class << self
        def create(name, base_dir, template_dir)
          dest = ::File.join(base_dir, name)
          FileUtils.mkdir(dest)
          FileUtils.cp_r(::File.join(template_dir, '.'), dest)
          local = new(dest)
          local.create_id
          local
        end

        def named(string, path)
          match = Dir.glob(::File.join(path, '*')).select{|entry| ::File.basename(entry) == string }[0]
          return unless (match && ::File.directory?(match) && ours?(match))
          return new(match) 
        end

        def ours?(dir)
          (Dir.exists?(::File.join(dir, 'audio')) && Dir.exists?(::File.join(dir, 'originals')))
        end


        def etc_file_accessor(*syms)
          syms.each do |sym|
            define_method(sym) do
              file('etc',"#{sym.to_s}.txt").read
            end
            define_method("#{sym.to_s}=".to_sym) do |value|
              file('etc',"#{sym.to_s}.txt").write!(value)
            end
            define_method("delete_#{sym.to_s}".to_sym) do
              file('etc',"#{sym.to_s}.txt").delete!
            end
          end
        end
      end #class << self

      etc_file_accessor :subtitle, :audio_is_on_www

      def tmp_dir
        ::File.join(path, 'etc', 'tmp')
      end

      def rm_tmp_dir
        FileUtils.rm_r(tmp_dir)
      end

      def audio_chunks
        Dir.glob(::File.join(path, 'audio', '*.mp3')).reject{|file| file.match(/\.all\.mp3$/)}.map{|path| Audio::File.new(path)}
      end

      def audio_remote_names(assignments=csv('csv/assignment.csv').read)
        assignments.map{|assignment| url_basename(assignment['audio_url']) }
      end


      def assignment_remote_names(assignments=csv('csv/assignment.csv').read)
        assignments.map{|assignment| url_basename(assignment['assignment_url']) }
      end

      def url_basename(url)
        ::File.basename(URI.parse(url).path)
      end

      def id
        file('etc','id.txt').read
      end

      def create_id
        if id 
          raise Error, "id already exists" 
        end
        file('etc','id.txt').write!(SecureRandom.hex(16))
      end

      def original_audio
        dir = ::File.join(path, 'originals')
        Dir.entries(dir).map{|entry| ::File.join(dir, entry) }.select do |path| 
          ::File.file?(path) &&
            not(::File.extname(path).downcase.eql?('html')) &&
            not(::File.basename(path).match(/^\./))
        end
      end

      def add_audio(paths, move=false)
        action = move ? 'mv' : 'cp'
        paths.each{|path| FileUtils.send(action, path, ::File.join(self.path, 'originals')) }
      end

      def finder_open
        system('open', @path)
      end

      def file(*relative_path)
        File.new(file_path(*relative_path))
      end

      def csv(*relative_path)
        File::CSV.new(file_path(*relative_path))
      end

      def file_path(*relative_path)
        ::File.join(@path, *relative_path)
      end

      class File
        def initialize(path)
          @path = path
        end

        def read
          if exists?
            IO.read(@path)
          end
        end

        def write!(data, mode='w')
          ::File.open(@path, mode) do |out|
            out << data
          end
        end

        def delete!
          if exists?
            ::File.delete(@path)
          end
        end

        def exists?
          ::File.exists?(@path)
        end

        class CSV < File
          include Enumerable
          require 'csv'

          def read
            rows = ::CSV.parse(super.to_s)
            headers = rows.shift or raise Error::File, "No CSV at #{@path}"
            rows.map{|row| Utility.array_to_hash(row, headers) }
          end

          def write!(hashes, headers=hashes.map{|h| h.keys}.flatten.uniq)
            super(::CSV.generate_line(headers) + hashes.map{|hash| ::CSV.generate_line(headers.map{|header| hash[header] }) }.join )
          end

          def write_arrays!(arrays, headers)
            write!(arrays.map{|array| Utility.array_to_hash(array, headers) }, headers)
          end

          def each
            read.each do |row|
              yield row
            end
          end

          def each!
            #each_with_index doesn't return the array, so we have to use each
            i = 0
            write!(each do |hash| 
                     yield(hash, i)
                     i += 1 
                   end)
          end
        end #CSV
      end #File
    end #Local

    class Audio
      require 'fileutils'

      def self.merge(files, dest)
        raise Error::Argument, "No files to merge" if files.empty?
        if files.size > 1
          Utility.system_quietly('mp3wrap', dest, *files.map{|file| file.path})
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
          raise Error::File, "No single quotes allowed in file names" if path.match(/'/)
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
          dest =  ::File.join(dir, "#{::File.basename(@path, '.*')}.mp3")
          Utility.system_quietly('ffmpeg', '-i', @path, '-acodec', 'libmp3lame', '-ab', "#{bitrate}k", '-ac', '2', dest)
          return self.class.new(dest)
        end

        def bitrate
          info = `ffmpeg -i '#{@path}' 2>&1`.match(/(\d+) kb\/s/)
          return info ? info[1] : nil
        end

        def split(interval_in_min_dot_seconds, base_name=::File.basename(@path, '.*'))
          #We have to cd into the wrapfile directory and do everything
          #there because old/packaged versions of mp3splt were
          #retarded at handling absolute directory paths
          dir = ::File.dirname(@path)
          Dir.chdir(dir) do
            Utility.system_quietly('mp3splt', '-t', interval_in_min_dot_seconds, '-o', "#{base_name}.@m.@s", ::File.basename(@path)) 
          end
          Dir.entries(dir).select{|entry| ::File.file?("#{dir}/#{entry}")}.reject{|file| file.match(/^\./)}.reject{|file| file.eql?(::File.basename(@path))}.map{|file| self.class.new("#{dir}/#{file}")}
        end

        def offset
          match = ::File.basename(@path).match(/\d+\.\d\d\b/)
          return match[0] if match
        end
      end #File
    end #Audio
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
      require 'text/format'
      require 'cgi'

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
        text = text.split("\n").map {|line| wrap_text(line) }.join("\n") 
        text.gsub!(/\n\n+/, "\n\n")
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
end #Typingpool
