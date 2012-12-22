module Typingpool
  class Filer

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
          path = File.join(in_dir, name)
          if File.exists?(path) && File.directory?(path)
            new(path)
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

      #Returns the files in the Filer::Dir directory as Filer
      #instances. Excludes files whose names start with a dot.
      def files
        ::Dir.entries(@path).select{|entry| File.file? file_path(entry) }.reject{|entry| entry.match(/^\./) }.map{|entry| self.file(entry) }
      end

      #Takes relative path elements as params just like the file
      #method. Returns a new Filer::Dir instance wrapping the
      #referenced subdir.
      def subdir(*relative_path)
        Dir.new(file_path(*relative_path))
      end

      #OS X specific. Opens the dir in the Finder via the 'open' command.
      def finder_open
        system('open', @path)
      end

      def file_path(*relative_path)
        File.join(@path, *relative_path)
      end

    end #Dir
  end #Filer
end #Typingpool
