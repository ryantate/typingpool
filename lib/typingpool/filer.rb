module Typingpool

  #Convenience wrapper for basic file operations. Base class for
  #wrappers for specialized file types (audio, CSV) and for file
  #collections.
  class Filer
    require 'fileutils'

    #Fully-expanded path to file
    attr_reader :path

    #Constructor.
    # ==== Params
    #[path] Fully expanded path to file.
    def initialize(path)
      @path = path
    end

    #Returns contents of file or nil if the file does not exist.
    def read
      if File.exists? @path
        IO.read(@path)
      end
    end

    #Write data to the file.
    def write(data, mode='w')
      File.open(@path, mode) do |out|
        out << data
      end
    end

    #Moves the underlying file AND updates the @path of the Filer instance.
    def mv!(to)
      FileUtils.mv(@path, to)
      if File.directory? to
        to = File.join(to, File.basename(path))
      end
      @path = to
    end

    #Filer objects always stringify to their path. We might change
    #this later such that to_str gives the path but to_s gives the
    #content of the file as text.
    def to_s
      @path
    end
    alias :to_str :to_s

    #Returns the underlying file as an IO stream. Convenient for
    #Project::Remote#put.
    def to_stream(mode='r')
      File.new(@path, mode)
    end

    #Returns the parent dir of the underlying file as a Filer::Dir
    #instance.
    def dir
      Filer::Dir.new(File.dirname(@path))
    end

    #Convenience wrapper for CSV files. Makes them Enumerable, so you
    #can iterate through rows with each, map, select, etc. You can
    #also modify in place with each!. See Filer base class for other
    #methods.
    class CSV < Filer
      include Enumerable
      require 'csv'

      #Reads into an array of hashes, with hash keys determined by the
      #first row of the CSV file. Parsing rules are the default for
      #CSV.parse. 
      def read
        raw = super or return
        rows = ::CSV.parse(raw.to_s)
        headers = rows.shift or raise Error::File, "No CSV at #{@path}"
        rows.map{|row| Utility.array_to_hash(row, headers) }
      end

      #Takes array of hashes followed by optional list of keys (by
      #default keys are determined by looking at all the
      #hashes). Lines are written per the defaults of
      #CSV.generate_line.
      def write(hashes, headers=hashes.map{|h| h.keys}.flatten.uniq)
        super(::CSV.generate_line(headers) + hashes.map{|hash| ::CSV.generate_line(headers.map{|header| hash[header] }) }.join )
      end

      #Takes an array of arrays, corresponding to the rows, and a list
      #of headers/keys to write at the top.
      def write_arrays(arrays, headers)
        write(arrays.map{|array| Utility.array_to_hash(array, headers) }, headers)
      end

      #Enumerate through the rows, with each row represented by a
      #hash.
      def each
        read.each do |row|
          yield row
        end
      end

      #Same as each, but any changes to the rows will be written back
      #out to the underlying CSV file.
      def each!
        #each_with_index doesn't return the array, so we have to use each
        i = 0
        write(each do |hash| 
                yield(hash, i)
                i += 1 
              end)
      end
    end #CSV

    #Convenience wrapper for audio files.You can convert to mp3s,
    #split into multiple files, and dynamically read the bitrate.
    class Audio < Filer
      require 'open3'

      #Does the file have a '.mp3' extension?
      def mp3?
        File.extname(@path).downcase.eql?('.mp3')
      end

      #Convert to mp3 via ffmpeg. 
      # ==== Params
      # [dest]    Filer object corresponding to the path the mp3 version
      #           should end up at.
      # [bitrate] If passed, bitrate should be an integer
      #           corresponding to kb/s. If not, we use the bitrate
      #           from the current file or, if that can't be read,
      #           default to 192kbps. Does not check if the file is
      #           already an mp3. Returns a new Filer::Audio
      #           representing the new mp3 file.
      # ==== Returns
      # Filer::Audio containing the new mp3.
      def to_mp3(dest=self.dir.file("#{File.basename(@path, '.*') }.mp3"), bitrate=nil)
        bitrate ||= self.bitrate || 192
        Utility.system_quietly('ffmpeg', '-i', @path, '-acodec', 'libmp3lame', '-ab', "#{bitrate}k", '-ac', '2', dest)
        File.exists?(dest) or raise Error::Shell, "Could not found output from `ffmpeg` on #{path}"
        self.class.new(dest.path)
      end

      #Reads the bitrate of the audio file via ffmpeg. Returns an
      #integer corresponding to kb/s, or nil if the bitrate could not
      #be determined.
      def bitrate
        out, err, status = Open3.capture3('ffmpeg', '-i', @path)
        bitrate = err.match(/(\d+) kb\/s/)
        return bitrate ? bitrate[1].to_i : nil
      end

      #Splits an mp3 into smaller files. 
      # ==== Params
      # [interval_in_min_dot_seconds] Split the file into chunks this
      #             large. The interval should be of the format
      #             minute.seconds, for example 2 minutes 15 seconds
      #             would be written as "2.15". For further details on
      #             interval format, consult the documentation for
      #             mp3split, a command-line unix utility.
      # [basename]  Name the new chunks using this base. Default is the
      #             basename of the original file.
      # [dest]      Destination directory for the new chunks as a
      #             Filer::Dir. Default is the same directory as the
      #             original file.

      # ==== Returns
      # Filer::Files containing the new files.
      def split(interval_in_min_dot_seconds, basename=File.basename(path, '.*'), dest=dir)
        #We have to cd into the wrapfile directory and do everything
        #there because old/packaged versions of mp3splt were
        #retarded at handling absolute directory paths
        ::Dir.chdir(dir.path) do
          Utility.system_quietly('mp3splt', '-t', interval_in_min_dot_seconds, '-o', "#{basename}.@m.@s", File.basename(path)) 
        end
        files = Filer::Files::Audio.new(dir.select{|file| File.basename(file.path).match(/^#{Regexp.escape(basename) }\.\d+\.\d+\.mp3$/) })
        if files.to_a.empty?
          raise Error::Shell, "Could not find output from `mp3splt` on #{path}"
        end
        if dest.path != dir.path
          files.mv!(dest)
        end
        files
      end

      #Extracts from the filename the offset time of the chunk
      #relative to the original from which it was split. Format is
      #minute.seconds. Suitable for use on files created by 'split'
      #method.
      def offset
        match = File.basename(@path).match(/\d+\.\d\d\b/)
        return match[0] if match
      end
    end #Audio

    #Handler for collection of Filer instances. Makes them enumerable,
    #Allows easy re-casting to Filer::Files subclasses,
    #and provides various other convenience methods.  
    class Files
      include Enumerable
      require 'fileutils'

      #Array of Filer instances included in the collection
      attr_reader :files

      #Constructor. Takes array of Filer instances.
      def initialize(files)
        @files = files
      end

      #Enumerate through Filer instances.
      def each
        files.each do |file|
          yield file
        end
      end

      #Cast this collection into a new Filer::Files subtype,
      #e.g. Filer::Files::Audio.
      # ==== Params
      # [sym] Symbol corresponding to Filer::Files subclass to cast
      # into. For example, passing :audio will cast into a
      # Filer::Files::Audio.
      # ==== Returns
      # Instance of new Filer::Files subclass
      def as(sym)
        self.class.const_get(sym.to_s.capitalize).new(files)
      end

      #Returns array of IO streams created by calling to_stream on
      #each Filer instance in the collection.
      def to_streams
        self.map{|file| file.to_stream }
      end

      #Calls mv! on each Filer instance in the collection. See
      #documentation for Filer#mv! for definition of "to" param and
      #for return value.
      def mv!(to)
        files.map{|file| file.mv! to }
      end

      #Handler for collection of Filer::Audio instances. Does
      #everything Filer::Files does, plus can batch convert to mp3 an
      #can merge the Filer::Audio instances into a single audio file,
      #provided they are in mp3 format.
      class Audio < Files
        #Constructor. Takes an array of Filer or Filer subclass instances.
        def initialize(files)
          @files = files.map{|file| self.file(file.path) }
        end

        def file(path)
          Filer::Audio.new(path)
        end

        #Batch convert Filer::Audio instances to mp3 format.
        # ==== Params
        # [dest_dir] Filer::Dir instance corresponding to directory
        #            into which mp3 file versions will be created.
        # [bitrate]  See documentation for Filer::Audio#bitrate.
        # ==== Returns
        # Filer::Files::Audio instance corresponding to new mp3
        # versions of the original files or, in the case where the
        # original file was already in mp3 format, corresponding to
        # the original files themselves.
        def to_mp3(dest_dir, bitrate=nil)
          mp3s = self.map do |file|
            if file.mp3?
              file
            else
              yield(file) if block_given?
              file.to_mp3(dest_dir.file("#{File.basename(file.path, '.*') }.mp3"), bitrate)
            end
          end
          self.class.new(mp3s)
        end

        #Merge Filer::Audio instances into a single new file, provided
        #they are all in mp3 format.
        # ==== Params
        #[into_file] Filer or Filer subclass instance corresponding to
        #the location of the new, merged file that should be created.
        # ==== Returns
        # Filer::Audio instance corresponding to the new, merged file.
        def merge(into_file)
          raise Error::Argument, "No files to merge" if self.to_a.empty?
          if self.count > 1
            Utility.system_quietly('mp3wrap', into_file, *self.to_a)
            written = File.join(into_file.dir, "#{File.basename(into_file.path, '.*') }_MP3WRAP.mp3")
            FileUtils.mv(written, into_file)
          else
            FileUtils.cp(self.first, into_file)
          end
          self.file(into_file.path)
        end
      end #Audio
    end #Files

    #Convenience wrapper for basic directory operations and for
    #casting files to specific filer types (CSV, Audio).
    class Dir < Files

      #Full expanded path to the dir
      attr_reader :path

      #Constructor. Takes full expanded path to the dir. Does NOT
      #create dir in the filesystem.
      def initialize(path)
        @path = path
      end

      class << self

        #Constructor. Takes full expanded path to the dir and creates
        #the dir in the filesystem. Returns new Filer::Dir.
        def create(path)
          FileUtils.mkdir(path)
          new(path)
        end

        #Constructor. Takes directory name and full expanded path of
        #the parent directory. If the so-named directory exists within
        #the parent directory, returns it. If not, returns nil.
        def named(name, in_dir)
          #TODO - Can just use File.exists? here, right?
          match = ::Dir.entries(in_dir).map{|entry| File.join(in_dir, entry) }.select do |entry| 
            (File.basename(entry) == name)  &&
              (File.directory? entry)
          end
          if match.first
            new(match.first)
          end
        end
      end #class << self

      #Filer::Dir isntances stringify to their path.
      def to_s
        @path
      end
      alias :to_str :to_s

      #Takes an aribtrary number of path elements relative to the
      #Filer::Dir instance. So a file in the subdir path/to/file.txt
      #would be referenced via file('path', 'to', 'file.txt'). Returns
      #a new Filer instance wrapping the referenced file. Does not
      #guarantee that the referenced file exists.
      def file(*relative_path)
        Filer.new(file_path(*relative_path))
      end

      #Same as file method, but returns a Filer::CSV.
      def csv(*relative_path)
        Filer::CSV.new(file_path(*relative_path))
      end

      #Same as file methd, but returns a Filer::Audio.
      def audio(*relative_path)
        Filer::Audio.new(file_path(*relative_path))
      end

      #Returns the files in the Filer::Dir directory as Filer
      #instances. Excludes files whose names start with a dot.
      def files
        ::Dir.entries(@path).select{|entry| File.file? file_path(entry) }.reject{|entry| entry.match(/^\./) }.map{|entry| self.file(entry) }
      end

      #Takes relative path elements as params just like the file
      #method. Returns a new Filer::Dir instance wrapping the
      #referenced subdir.
      def subdir(*relative_path)
        self.class.new(file_path(*relative_path))
      end

      #OS X specific. Opens the dir in the Finder via the 'open' command.
      def finder_open
        system('open', @path)
      end

      #private

      def file_path(*relative_path)
        File.join(@path, *relative_path)
      end

    end #Dir
  end #Filer
end #Typingpool
