module Typingpool
  class Filer

    #Handler for collection of Filer instances. Makes them enumerable,
    #Allows easy re-casting to Filer::Files subclasses,
    #and provides various other convenience methods.  
    class Files
      include Enumerable
      include Utility::Castable
      require 'fileutils'
      require 'typingpool/filer/files/audio'

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
        #super calls into Utility::Castable mixin
        super(sym, files)
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
    end #Files
  end #Filer
end #Typingpool
