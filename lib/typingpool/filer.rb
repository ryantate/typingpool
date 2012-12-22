module Typingpool

  #Convenience wrapper for basic file operations. Base class for
  #wrappers for specialized file types (audio, CSV) and for file
  #collections.
  class Filer
    require 'fileutils'
    include Utility::Castable
    include Comparable

    #Fully-expanded path to file
    attr_reader :path

    #Constructor.
    # ==== Params
    #[path] Fully expanded path to file.
    #[encoding] Optional. Encoding for all text operations on the
    #           file. Should be compatiable with :encoding arg to
    #           IO.read. Default is 'UTF-8'.
    def initialize(path, encoding='UTF-8')
      @path = path
      @encoding = encoding
    end

    def <=>(other)
      path <=> other.path
    end

    #Returns contents of file or nil if the file does not exist. 
    def read
      if File.exists? @path
        IO.read(@path, :encoding => @encoding)
      end
    end

    #Write data to the file.
    def write(data, mode='w')
      File.open(@path, mode, :encoding => @encoding) do |out|
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

    #Returns the underlying file as an IO stream. Convenient for
    #Project::Remote#put.
    def to_stream(mode='r')
      File.new(@path, mode, :encoding => @encoding)
    end

    #Filer objects always stringify to their path. We might change
    #this later such that to_str gives the path but to_s gives the
    #content of the file as text.
    def to_s
      @path
    end
    alias :to_str :to_s

    #Returns the parent dir of the underlying file as a Filer::Dir
    #instance.
    def dir
      Filer::Dir.new(File.dirname(@path))
    end

    #Cast this file into a new Filer subtype, e.g. Filer::Audio.
    # ==== Params
    # [sym] Symbol corresponding to Filer subclass to cast into. For
    # example, passing :audio will cast into a Filer::Audio.
    # ==== Returns
    # Instance of new Filer subclass
    def as(sym)
      #super calls into Utility::Castable mixin
      super(sym, @path)
    end
  end #Filer
    require 'typingpool/filer/csv'
    require 'typingpool/filer/audio'
    require 'typingpool/filer/files'
    require 'typingpool/filer/dir'
end #Typingpool
