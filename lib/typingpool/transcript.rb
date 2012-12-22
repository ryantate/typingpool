module Typingpool
  #This is the model class for Typingpool's final and most important
  #output, a transcript of the Project audio in HTML format, with
  #embedded audio. A Transcript instance is actually an enumerable
  #container for Transcript::Chunk instances. Each Transcript::Chunk
  #corresponds to an Amazon::HIT and to an audio "chunk" (file) that
  #has been transcribed and which is part of a larger recording.
  #
  #This class is likey to be done away with in the next few point
  #versions of Typingpool. Functionality and data unique to
  #Transcipt::Chunk can probably be rolled into
  #Amazon::HIT. Transcript itself can probably be folded into Project,
  #which would become a HIT container, and then we'd pass Project
  #instances to the output template.
  class Transcript
    include Enumerable

    #Get/set the title of the transcript, typically corresponds to the name of the
    #associated Project
    attr_accessor :title

    #Get/set the subtitle of the transcript, corresponds to Project#local#subtitle
    #(a.k.a data/subtitle.txt in the project dir)
    attr_accessor :subtitle

    #Constructor. Takes an optional title (see above for explanation
    #of title) and an optional array of Transcript::Chunk instances.
    def initialize(title=nil, chunks=[])
      @title = title
      @chunks = chunks
    end

    #Iterate of the Transcript::Chunk instances
    def each
      @chunks.each do |chunk|
        yield chunk
      end
    end

    #Takes an index, returns the Transcript::Chunk at that index.
    def [](index)
      @chunks[index]
    end

    #Returns chunks joined by double newlines
    def to_s
      @chunks.join("\n\n")
    end
    
    #Takes a Transcript::Chunk instance and adds it to the Transcript instance.
    def add_chunk(chunk)
      @chunks.push(chunk)
    end

    require 'typingpool/transcript/chunk'
  end #Transcript 
end #Typingpool
