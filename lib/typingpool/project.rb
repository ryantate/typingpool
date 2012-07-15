module Typingpool

  #Class representing a transcription job, a job typically associated
  #with a single interview or other event and with one or more audio
  #files containing recordings of that event.  A project is
  #associated, locally, with a filesystem directory. On Amazon
  #Mechanical Turk, a Project is associated with various HITs. A
  #project is also associated with audio files on a remote server.
  class Project
    require 'uri'

    #Returns a time interval corresponding to the length of each audio
    #chunk within the project. (Each chunk may be transcribed
    #separately.)
    attr_reader :interval

    #Returns the desired bitrate of processed audio files.
    attr_reader :bitrate

    #Accessor for the name of the project (sometimes referred to as
    #the 'title' in command line code)
    attr_accessor :name 

    #Accessor for the Config object associated with the project.
    attr_accessor :config

    #Constructor. Takes the project name and an optional Config
    #instance (default is the default Config.file). Project does not
    #have to exist locally or remotely.
    def initialize(name, config=Config.file)
      Local.valid_name?(name) or raise Error::Argument::Format, "The project name '#{name}' is invalid; a project name must be a valid name for a directory in the local filesystem. Eliminate '/' or any other illegal character."
      @name = name
      @config = config
    end

    class << self
      #Constructor. Like 'new', except it will only return an instance
      #if the project already exists locally.
      def local(*args)
        project = new(*args)
        if project.local
          return project
        end
      end

      #Constructor. Like 'local', except it will only return an
      #instance if the local project has the specified id. Id should
      #be passed as the last (third) param.
      def local_with_id(*args)
        id = args.pop
        if project = local(*args)
          if project.local.id == id
            return project
          end
        end
      end
    end #class << self

    #Constructs and returns a Project::Remote instance associated with
    #this Project instance. Takes an optional Config instance; default
    #is project.config.
    def remote(config=@config)
      Remote.from_config(@name, config)
    end

    #Constructs and returns a Project::Local instance associated with
    #this Project instance IF the project exists at the appropriate
    #location in the filesystem. Takes an optional path to a base
    #directory to look in; default is project.config.transcripts.
    def local(dir=@config.transcripts)
      Local.named(@name, dir) 
    end

    #Creates a local filesystem directory corresponding to the project
    #and constructs and returns a Project::Local instance associated
    #with that directory and with this Project instance. Takes an
    #optional path to a base directory in which to create the project
    #directory; default is project.config.transcripts.
    def create_local(basedir=@config.transcripts)
      Local.create(@name, basedir, File.join(Utility.lib_dir, 'templates', 'project'))
    end

    #Takes a time specification for setting the project.interval. The
    #time specification may be an integer corresponding to the nuymber
    #of secods or a colon-delimited time of the format HH:MM::SS.ssss,
    #where the hour and fractional seconds components are optional.
    def interval=(mmss)
      formatted = mmss.to_s.match(
                                  /^((\d+)|((\d+:)?(\d+):(\d\d)))(\.(\d+))?$/
                                  ) or raise Error::Argument::Format, "Interval does not match nnn or [nn:]nn:nn[.nn]"
      @interval = (formatted[2] || ((formatted[4].to_i * 60 * 60) + (formatted[5].to_i * 60) + formatted[6].to_i)).to_i
      @interval += ("0.#{formatted[8]}".to_f) if formatted[8]
    end

    #Returns the project.interval in a format understood by the Unix
    #utility mp3splt: $min.$sec[.01-99].
    def interval_as_min_dot_sec
      seconds = @interval % 60
      if seconds > seconds.to_i
        #mpl3splt takes fractions of a second to hundredths of a second precision
        seconds = seconds.round(2)
      end
      min_dot_sec = "#{(@interval.to_i / 60).floor}.#{seconds}"
    end

    #Takes an integer for setting the project.bitrate. The integer
    #should correspond to kilobits per second (kbit/s or kbps). This
    #is used as a target when converting to mp3 (when it's neccesary
    #to do so).
    def bitrate=(kbps)
      raise Error::Argument::Format, 'bitrate must be an integer' if kbps.to_i == 0
      @bitrate = kbps
    end


    #Writes a CSV file into project.local directory, storing information about the specified files.
    # ==== Params
    # [:path]         Relative path where the file will be written. Array of
    #                 relative path elements. See Filer::Dir#file docs
    #                 for details.
    # [:urls]         Array of URLs corresponding to project files.
    # [:chunk]        Length of the audio chunk in MM:SS format. See the
    #                 Project#interval documentation for further
    #                 details.
    # [:unusual]      Optional. Array of unusual words spoken in the
    #                 audio to be transcribed. This list is ultimately
    #                 provided to transcribers to aid in their work.
    # [:voices]       Optional. Array of hashes, with each having a :name and
    #                 :description element. Each hash corresponds to a
    #                 person whose voice is on the audio. These
    #                 details are ultimately provided to transcibers
    #                 to allow them to correctly label sections of the
    #                 transcript
    # ==== Returns
    # Path to the resulting CSV file.
    def create_assignment_csv(args)
      [:path, :urls, :chunk, :audio_upload_confirms].each{|arg| args[arg] or raise Error::Argument, "Missing arg '#{arg}'" }
      headers = ['audio_url', 'audio_upload_confirmed', 'project_id', 'chunk', 'unusual', (1 .. args[:voices].count).map{|n| ["voice#{n}", "voice#{n}title"]}].flatten
      csv = []
      args[:urls].each_with_index do |url, i|
        csv << [url, (args[:audio_upload_confirms][i] || 0), local.id, args[:chunk], args[:unusual].join(', '), args[:voices].map{|v| [v[:name], v[:description]]}].flatten
      end
      local.csv(*args[:path]).write_arrays(csv, headers)
      local.file_path(*args[:path])
    end

    #Takes an array of file paths, file names, or Filer
    #instances. Returns an array of file basenames. The return
    #basenames will be the original basenames with the project id and
    #a random or pseudo-random string insterted between the root
    #basename and the file extension. The purpose of this is to make
    #it difficult to guess the name of one remote file after seeing
    #another, thus significantly complicating any attempt to download
    #the entirety of a project (such as a journalistic interview)
    #after seeing a single assignment on Amazon Mechanical Turk. (This
    #should be considered an effort at obfuscation. It is not any
    #guarantee of true security.)
    def create_remote_names(files)
      files.map do |file|
        name = [File.basename(file, '.*'), local.id, pseudo_random_uppercase_string].join('.')
        name += File.extname(file) if not(File.extname(file).to_s.empty?)
        name
      end
    end

    #Returns a Regexp for breaking an URL down into the original
    #project basename as well as the audio chunk offset. This probably
    #shouldn't need to exist. (TODO: make this unneccesary.)
    def self.url_regex
      Regexp.new('.+\/((.+)\.(\d+)\.(\d\d)\.[a-fA-F0-9]{32}\.[A-Z]{6}(\.\w+))')
    end

    #Takes an url. Returns the basename of the associated
    #project.local file. This probably shouldn't need to exist. (TODO:
    #Make this unneccesary.)
    def self.local_basename_from_url(url)
      matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
      URI.unescape([matches[2..4].join('.'), matches[5]].join)
    end

    protected

    #Takes an optional string length (default 6). Returns a string of
    #pseudo-random uppercase letters of the specified length. Should
    #probably move this into Utility. TODO
    def pseudo_random_uppercase_string(length=6)
      (0...length).map{(65 + rand(25)).chr}.join
    end

    #Representation of the Project instance on remote servers. This is
    #basically a collection of audio files to be transcribed and HTML
    #files containing instructions and a form for the
    #transcribers. The backend can be Amazon S3 (the default) or an
    #SFTP server. Each backend is encapsulated in its own subclass. A
    #backend subclass must provide a 'put' method, which takes an
    #array of IO streams and an optional array of remote file
    #basenames; a 'remove' method, which takes an array of remote file
    #basenames; and the methods 'host' and 'path', which return the
    #location of the destination server and destination directory,
    #respectively.
    #
    #Thus, there will always be 'put', 'remove', 'host' and 'path'
    #methods available, in addition to the Project::Remote methods
    #outlined below.
    class Remote

      #The project name
      attr_accessor :name

      #Constructor. Takes the project name and a Config
      #instance. Returns a Project::Remote::S3 or
      #Project::Remote::SFTP instance, depending on the particulars of
      #the Config. If there are sufficient config params to return
      #EITHER an S3 or SFTP subclass, it will prefer the SFTP
      #subclass.
      def self.from_config(name, config)
        if config.sftp
          SFTP.new(name, config.sftp)
        elsif config.amazon && config.amazon.bucket
          S3.new(name, config.amazon)
        else
          raise Error, "No valid upload params found in config file (SFTP or Amazon info)"
        end
      end

      #Like project.remote.remove, except it takes an array of URLs
      #instead an array of remote basenames, saving you from having to
      #manually extract basenames from the URL.
      def remove_urls(urls)
        basenames = urls.map{|url| url_basename(url) } 
        remove(basenames){|file| yield(file) if block_given? }
      end

      #Given a file path, returns the URL to the file path were it to
      #be uploaded by this instance.
      def file_to_url(file)
        "#{@url}/#{URI.escape(file)}"
      end

      #Given an URL, returns the file portion of the path, given the
      #configuration of this instance.
      def url_basename(url)
        basename = url.split("#{self.url}/").last or raise Error "Could not find base url '#{self.url}' within longer url '#{url}'"
        URI.unescape(basename)
      end

      #Subclass for storing remote files on Amazon Simple Storage
      #Service (S3)
      class S3 < Remote
        require 'aws/s3'

        #An Amazon Web Services "Access Key ID." Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :key

        #An Amazon Web Services "Secret Access Key." Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :secret

        #The S3 "bucket" where uploads will be stores. Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :bucket

        #Returns the base URL, which is prepended to the remote
        #files. This is either the 'url' attribute of the
        #Config#amazon value passed to Project::Remote::S3.new or, if
        #that attribute is not set, the value returned by
        #'default_url' (e.g. "https://bucketname.s3.amazonaws.com").
        attr_reader :url

        #Constructor. Takes the project name and the result of calling
        #the 'amazon' method on a Config instance (i.e. the amazon
        #section of a Config file).
        def initialize(name, amazon_config)
          @name = name
          @config = amazon_config
          @key = @config.key or raise Error::File::Remote::S3, "Missing Amazon key in config"
          @secret = @config.secret or raise Error::File::Remote::S3, "Missing Amazon secret in config"
          @bucket = @config.bucket or raise Error::File::Remote::S3, "Missing Amazon bucket in config"
          @url = @config.url || default_url
        end

        #The remote host (server) name, parsed from #url
        def host
          URI.parse(@url).host
        end

        #The remote path (directory), pased from #url
        def path
          URI.parse(@url).path
        end

        #Upload files/strings to S3, optionally changing the names in the process.
        # ==== Params
        #[io_streams] Enumerable collection of IO objects, like a File
        #             or StringIO instance.
        #[as]         Optional if the io_streams are File instances. Array of
        #             file basenames, used to name the destination
        #             files. Default is the basename of the Files
        #             passed in as io_streams.
        # ==== Returns
        #Array of URLs corresponding to the uploaded files.
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
            file_to_url(dest)
          end #batch
        end

        #Delete objects from S3.
        # ==== Params
        #[files] Enumerable collection of file names. Should NOT
        #        include the bucket name (path).
        # ==== Returns
        #Array of booleans corresponding to whether the delete call
        #succeeded.
        def remove(files)
          batch(files) do |file, i|
            yield(file) if block_given?
            AWS::S3::S3Object.delete(file, @bucket)
          end
        end

        protected

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
      end #S3

      #Subclass for storing remote files on an SFTP server. Only
      #public/private key authentication has been tested. There is not
      #yet any provision for password-based authentication, though
      #adding it should be trivial.
      class SFTP < Remote
        require 'net/sftp'

        #Returns the remote host (server) name. This is set from
        #Config#sftp#host.
        attr_reader :host

        #Returns the remote path (directory). This is set from
        #Config#sftp#path.
        attr_reader :path

        #Returns the name of the user used to log in to the SFTP
        #server. This is et from Config#sftp#user.
        attr_reader :user

        #Returns the base URL, which is prepended to the remote
        #files. This is set from Config#sftp#url.
        attr_reader :url

        #Constructor. Takes the project name and a Config#sftp.
        def initialize(name, sftp_config)
          @name = name
          @config = sftp_config   
          @user = @config.user or raise Error::File::Remote::SFTP, "No SFTP user specified in config"
          @host = @config.host or raise Error::File::Remote::SFTP, "No SFTP host specified in config"
          @url = @config.url or raise Error::File::Remote::SFTP, "No SFTP url specified in config"
          @path = @config.path || ''
        end

        #See docs for Project::Remote::S3#put.
        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          begin
            i = 0
            batch(io_streams) do |stream, connection|
              dest = as[i]
              i += 1
              yield(stream, dest) if block_given?
              connection.upload(stream, join_with_path(dest))
              file_to_url(dest)
            end
          rescue Net::SFTP::StatusException => e
            raise Error::File::Remote::SFTP, "SFTP upload failed: #{e.description}"
          end
        end

        #See docs for Project::Remote::S3#remove.
        def remove(files)
          requests = batch(files) do |file, connection|
            yield(file) if block_given?
            connection.remove(join_with_path(file))
          end
          failures = requests.reject{|request| request.response.ok?}
          if not(failures.empty?)
            summary = failures.map{|request| request.response.to_s}.join('; ')
            raise Error::File::Remote::SFTP, "SFTP removal failed: #{summary}"
          end
        end

        protected

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

        def join_with_path(file)
          if @path
            [@path, file].join('/')
          else
            file
          end
        end

      end #SFTP
    end #Remote

    #Representation of the Project instance in the local
    #filesystem. Subclass of Filer::Dir; see Filer::Dir docs for
    #additional details.
    #
    #This is basically a local dir with various subdirs and files
    #containing the canonical representation of the project, including
    #data on remote resources, the project ID and subtitle, the audio files
    #themselves, and, when complete, an HTML transcript of that audio,
    #along with supporting CSS and Javascript files.
    class Local < Filer::Dir
      require 'fileutils'
      require 'securerandom'

      #Returns the dir path.
      attr_reader :path

      class << self
        #Constructor. Creates a directory in the filesystem for the
        #project.
        #
        # ==== Params
        # [name]         Name of the associated project.
        # [base_dir]     Path to the local directory into which the project
        #                dir should be placed.
        # [template_dir] Path to the dir which will be used as a base
        #                template for new projects.
        # ==== Returns
        # Project::Local instance.
        def create(name, base_dir, template_dir)
          local = super(File.join(base_dir, name))
          FileUtils.cp_r(File.join(template_dir, '.'), local)
          local.create_id
          local
        end

        #Takes the name of a project and a path. If there's a
        #directory with a matching name in the given path whose file
        #layout indicates it is a Project::Local instance (see 'ours?'
        #docs), returns a corresponding Project::Local instance.
        def named(string, path)
          match = super
          if match && ours?(match)
            return match
          end
          return
        end

        #Takes a Filer::Dir instance. Returns true or false depending on whether
        #the file layout inside the dir indicates it is a
        #Project::Local instance.
        def ours?(dir)
          File.exists?(dir.subdir('audio')) && File.exists?(dir.subdir('audio', 'originals'))
        end

        #Takes the name of a project and returns true if it is a valid
        #name for a directory in the local filesystem, false if not.
        def valid_name?(name)
          Utility.in_temp_dir do |dir|
            begin
              FileUtils.mkdir(File.join(dir, name))
            rescue Errno::ENOENT
              return false
            end #begin
            return File.exists?(File.join(dir, name))
          end #Utility.in_temp_dir do...
        end

        #Takes one or more symbols. Adds corresponding getter/setter
        #and delete method(s) to Project::Local, which read (getter)
        #and write (setter) and delete corresponding text files in the
        #data directory.
        #
        #So, for example, 'data_file_accessor :name' would allow you
        #to later create the file 'data/foo.txt' in the project dir by
        #calling 'project.local.name = "Foo"', read that same file via
        #'project.local.name', and delete the file via
        #'project.local.delete_name'
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

      #Calling 'subtitle' will read 'data/subtitle.txt'; calling
      #'subtitle=' will write 'data/subtitle.txt'; calling
      #'delete_subtitle' will delete 'data/subtitle.txt'.
      data_file_accessor :subtitle

      #Calling 'audio_is_on_www' will read 'data/audio_is_on_www.txt';
      #calling 'audio_is_on_www=' will write
      #'data/audio_is_on_www.txt'; calling 'delete_audio_is_on_www'
      #will delete 'data/audio_is_on_www.txt'.
      data_file_accessor :audio_is_on_www

      #Returns the ID of the project, as stored in 'data/id.txt'.
      def id
        file('data','id.txt').read
      end

      #Creates a file storing the canonical ID of the project in
      #'data/id.txt'. Raises an exception if the file already exists.
      def create_id
        if id 
          raise Error, "id already exists" 
        end
        file('data','id.txt').write(SecureRandom.hex(16))
      end
    end #Local
  end #Project
end #Typingpool
