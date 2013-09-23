module Typingpool

  #Hierarchical config object. Can be read from a YAML file and is
  #often modified at runtime, for example in response to script flags.
  #
  #==Fields
  #  All listed defaults are populated when you run tp-install.
  #===Required
  #  [transcripts] Unexpanded path to working directory for
  #                transcripts. This is where tp-make creates new
  #                transcript projects, and where other scripts like
  #                tp-assign, tp-review and tp-finish look for
  #                them. Default: On systems with a ~/Desktop (like OS
  #                X), ~/Desktop/Transcripts. Elsewhere,
  #                ~/transcripts.
  #====amazon
  #  [key]    An Amazon Web Services "Access Key ID." Default: none.
  #  [secret] An Amazon Web Services "Secret Access Key." Default: none.
  #  [bucket] The name of the "bucket" on Amazon S3 where your uploads
  #           will be stored. Not required if you specify SFTP config
  #           instead (see below). Default: Generated for you when you
  #           run tp-install.
  #
  #===Optional
  #  [cache]     Unexpanded path to the cache file (pstore). Default:
  #              ~/.typingpool.cache
  #  [templates] Unexpanded path to directory for user-created
  #              templates. Will be searched before looking in the
  #              template dir within the app. Default: 'templates' or
  #              'Templates' (OS X) dir inside the transcripts dir.
  #====amazon
  #  [url] Base URL to use when linking to files uploaded to S3. You
  #        may want to use this if you do custom domain mapping on
  #        S3. Default is https://$bucket.s3.amazonaws.com.
  #====sftp
  #If you provide SFTP config, the specified SFTP server will be used
  #to host remote mp3 and html files rather than Amazon S3. At
  #minimum, you must provide a user, host, and URL. SFTP will work
  #fine with public-key authentication (passwordless login). In fact,
  #I've not bothered to add password support yet.
  #  [user] SFTP username
  #  [host] SFTP server
  #  [path] Files will be uploaded into this path. Optional.
  #  [url]  Base URL to use when linking to files uploaded using the
  #         preceding config.
  #====assign
  #Defaults for tp-assign.
  #  [reward]   Pay per transcription chunk in U.S. dollars. Default: 0.75.
  #  [deadline] Length of time a worker has to complete a
  #             transcription job after accepting it (HIT
  #             'AssignmentDurationInSeconds' in the Mechanical Turk
  #             API). For details on the format, see docs for
  #             Utility.timespec_to_seconds. Default: 3h.
  #  [approval] Length of time before a submitted transcription job is
  #             automatically approved (HIT
  #             'AutoApprovalDelayInSeconds' in the Mechanical Turk
  #             API). For details on the format, see docs for
  #             Utility.timespec_to_seconds. Default: 1d.
  #  [lifetime] Length of time before a transcription job is no longer
  #             available to be accepted (HIT 'LifetimeInSeconds' in
  #             the Mechanical Turk API). For details on the format,
  #             see docs for Utility.timespec_to_seconds. Default: 2d.
  #  [qualify]  An array of qualifications with which to filter workers
  #             who may accept a transcript job. The first part of the
  #             qualification should be the string form of a key in
  #             RTurk::Qualifications.types (see
  #             https://github.com/mdp/rturk/blob/master/lib/rturk/builders/qualification_builder.rb
  #             ). The second part should be one of the following
  #             comparators: > >= < <= == != exists. The optional
  #             third part is a value. Default: ['approval_rate >=
  #             95'].
  #  [keywords] An array of keywords with which to tag each
  #             transcription job. Default: ['transcription', 'audio',
  #             'mp3'].
  #
  #==API
  #Values are read via same-named methods and set via same-named equals methods, like so:
  #  transcript_path = config.transcripts
  #  config.transcripts = new_path
  #
  #Nested sections are created simply by declaring a nested class
  #(which should typically inherit from Config, even if nested several
  #levels lower).
  #
  #Fields can be assigned special behaviors:
  #
  #  class Config
  #    class Root < Config
  #      local_path_reader :transcripts
  #      class SFTP < Config
  #        never_ends_in_slash_reader :url
  #      end
  #    end
  #  end
  #
  #  conf = Typingpool::Config.file
  #  conf.transcripts = '~/Documents/Transcripts'
  #  puts conf.transcripts #'/Volumes/Redsector/Users/chad/Documents/Transcripts'
  #  conf.sftp.url = 'http://luvrecording.s3.amazonaws.com/'
  #  puts conf.sftp.url #'http://luvrecording.s3.amazonaws.com'
  #
  class Config    
    require 'yaml'

    @@default_file = "~/.typingpool"

    def initialize(params)
      @param = params
    end

    class << self
      #Constructor.
      # ==== Params
      #[path] Fully expanded path to YAML file.
      # ==== Returns
      #Config instance.
      def file(path=File.expand_path(default_file))
        Root.new(YAML.load(IO.read((path))))
      end

      #Will always return ~/.typingpool unless you subclass. Will be
      #handed to File.expand_path before use.
      def default_file
        @@default_file
      end

      #Returns a new Config instance, empty except for the values
      #included in lib/templates/config.yml
      def from_bundled_template
        file(File.join(Utility.lib_dir, 'templates', 'config.yml'))
      end

      #protected

      #Define a field in a Config subclass as a local path. Reads on
      #that field will be filtered through File.expand_path.
      def local_path_reader(*syms)
        define_reader(*syms) do |value|
          File.expand_path(value) if value
        end
      end

      #Define a field in a Config subclass as never ending in
      #'/'. Useful for URLs and SFTP path specs. When a field is set
      #to a value ending in '/', the last character is stripped.
      def never_ends_in_slash_reader(*syms)
        define_reader(*syms) do |value|
          value.sub(/\/$/, '') if value
        end
      end

      #Define a field in a Config subclass as a time-length
      #specification. For format details, see docs for
      #Utility.timespec_to_seconds.
      def time_accessor(*syms)
        define_accessor(*syms) do |value|
          Utility.timespec_to_seconds(value) or raise Error::Argument::Format, "Can't convert '#{value}' to time"
        end
      end

      def define_reader(*syms, &block)
        #explicit block passing to avoid sefault in 1.9.3-p362
        syms.each do |sym|
          define_method(sym) do
            value = @param[sym.to_s]
            block.call(value)
          end
        end
      end

      def define_writer(*syms, &block)
        #explicit block passing to avoid sefault in 1.9.3-p362
        syms.each do |sym|
          define_method("#{sym.to_s}=".to_sym) do |value|
            @param[sym.to_s] = block.call(value)
          end
        end
      end

      def define_accessor(*syms, &block)
        #explicit block passing to avoid sefault in 1.9.3-p362
        define_reader(*syms) do |value|
          block.call(value) if value
        end
        define_writer(*syms) do |value|
          block.call(value)
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

    #All fields as raw key-value pairs. For nested subclasses, the
    #value is another hash.
    def to_hash
      @param
    end

    #Read the raw data for a field
    def [](key)
      @param[key]
    end

    #Set the raw data for a field
    def []=(key, value)
      @param[key] = value
    end

    def method_missing(meth, *args)
      equals_param = equals_method?(meth)
      if equals_param
        args.count == 1 or raise Error::Argument, "Wrong number of args (#{args.count} for 1)"
        return @param[equals_param] = args[0]
      end
      args.empty? or raise Error::Argument, "Too many args #{meth} #{args.join('|')}"
      value = @param[meth.to_s]
      if self.class.subklass?(meth.to_s) && value
        return self.class.subklass?(meth.to_s).new(value)
      end
      value
    end

    protected

    def equals_method?(meth)
      match = meth.to_s.match(/([^=]+)=$/) or return
      return match[1]
    end
  end #Config
    require 'typingpool/config/root'
end #Typingpool
