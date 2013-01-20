module Typingpool

  #Class representing a transcription job, a job typically associated
  #with a single interview or other event and with one or more audio
  #files containing recordings of that event.  A project is
  #associated, locally, with a filesystem directory. On Amazon
  #Mechanical Turk, a Project is associated with various HITs. A
  #project is also associated with audio files on a remote server.
  class Project
    require 'uri'
    require 'typingpool/project/local'
    require 'typingpool/project/remote'

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
      Local.valid_name?(name) or raise Error::Argument::Format, "Must be a valid name for a directory in the local filesystem. Eliminate '/' or any other illegal character."
      @name = name
      @config = config
    end

    #Constructs and returns a Project::Remote instance associated with
    #this Project instance. Takes an optional Config instance; default
    #is project.config.
    def remote(config=@config)
      Remote.from_config(config)
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
                                  /^((\d+)|((\d+:)?(\d+):(\d\d)))$/
                                  ) or raise Error::Argument::Format, "Required format is SS, or MM:SS, or HH:MM:SS"
      @interval = (formatted[2] || ((formatted[4].to_i * 60 * 60) + (formatted[5].to_i * 60) + formatted[6].to_i)).to_i
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
      raise Error::Argument::Format, 'Should be an integer corresponding to kb/s' if kbps.to_i == 0
      @bitrate = kbps
    end


    #Writes a CSV file into project.local directory, storing information about the specified files.
    # ==== Params
    # [:path]         Relative path where the file will be written. Array of
    #                 relative path elements. See Filer::Dir#file docs
    #                 for details.
    # [:urls]         Array of URLs corresponding to project files.
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
      [:path, :urls].each{|arg| args[arg] or raise Error::Argument, "Missing arg '#{arg}'" }
      headers = ['audio_url',
                 'project_id',
                 'unusual',
                 'chunk',
                 'chunk_hours',
                 'chunk_minutes',
                 'chunk_seconds',
                 'voices_count',
                 (1 .. args[:voices].count).map{|n| ["voice#{n}", "voice#{n}title"]}
                ].flatten
      csv = args[:urls].map do |url|
        [url, 
         local.id,
         args[:unusual].join(', '),
         interval_as_time_string,
         interval_as_hours_minutes_seconds.map{|n| (n == 0) ? nil : n },
         args[:voices].count,
         args[:voices].map{|v| [v[:name], v[:description]]}
        ].flatten
      end
      local.file(*args[:path]).as(:csv).write_arrays(csv, headers)
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

    def interval_as_hours_minutes_seconds
      seconds = interval or return
      hours = seconds / (60 * 60)
      seconds = seconds % (60 * 60)
      minutes = seconds / 60
      seconds = seconds % 60
      [hours, minutes, seconds]
    end

    #Returns interval as [HH:]MM:SS.
    def interval_as_time_string
      hms = interval_as_hours_minutes_seconds
      hms.shift if hms.first == 0
      #make sure seconds column is zero-padded and, if there are
      #hours, do the same to the minutes column
      (1 - hms.count .. -1).each{|i| hms[i] = hms[i].to_s.rjust(2, '0') }
      hms.join(":")
    end
  end #Project
end #Typingpool
