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

    #Transcript::Chunk is the model class for one transcription by one
    #Mechanical Turk worker of one "chunk" (a file) of audio, which in
    #turn is a portion of a larger recording (for example, one minute
    #of a 60 minute interview). It is basically parallel and similar
    #to an Amazon::HIT instance. Transcript is a container for these
    #chunks, which know how to render themselves as text and HTML.
    class Chunk
      require 'cgi'
      require 'text/format'

      #Get/set the raw text of the transcript
      attr_accessor :body

      #Get/set the Amazon ID of the Mechanical Turk worker who
      #transcribed the audio into text
      attr_accessor :worker

      #Get/set the id of the Amazon::HIT associated with this chunk
      attr_accessor :hit

      #Get/set the id of the Project#local associated with this chunk
      attr_accessor :project

      #Return the offset associated with the chunk, in MM:SS
      #format. This corresponds to the associated audio file, which is
      #a chunk of a larger recording and which starts at a particular
      #time offset, for example from 1:00 (the offset) to 2:00 (the
      #next offset).
      #
      #
      #This should be updated to return HH:MM:SS and MM:SS.sss when
      #appropriate, since in Project#interval we use that format and
      #allow audio to be divided into such units. (TODO)
      attr_reader :offset

      #Returns the offset in seconds. So for an offset of 1:00 would return 60.
      attr_reader :offset_seconds

      #Returns the name of the remote audio file corresponding to this
      #chunk. The remote file has the project ID and pseudo random
      #characters added to it.
      attr_reader :filename

      #Returns the name of the local audio file corresponding to this
      #chunk.
      attr_reader :filename_local

      #Returns the URL of the remote audio transcribed in the body of
      #this chunk.
      attr_reader :url

      #Constructor. Takes the raw text of the transcription.
      def initialize(body)
        @body = body
      end

      #Sorts by offset seconds.
      def <=>(other)
        self.offset_seconds <=> other.offset_seconds
      end

      #Takes an URL. As an important side effect, sets various
      #attributes, including url, filename, filename_local, offset and
      #offset_seconds. So setting Chunk#url= http://whateverwhatever
      #is an important step in populating the instance.
      def url=(url)
        #http://ryantate.com/transfer/Speech.01.00.ede9b0f2aed0d35a26cef7160bc9e35e.ISEAOM.mp3
        matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
        @url = matches[0]
        @filename = matches[1]
        @filename_local = Project.local_basename_from_url(@url)
        @offset = "#{matches[3]}:#{matches[4]}"
        @offset_seconds = (matches[3].to_i * 60) + matches[4].to_i
      end

      #Takes an optional callback. If a callback is provided, it is
      #passed a new Text::Format instance to configure, and then the
      #text is wrapped and formatted by calling the 'format' method on
      #that Text::Format instance. If no callbackis passed,
      #Text::Format#format will NOT be used on the text.
      #
      #Returns the text with newlines normalized to Unix format, runs
      #of newlines shortened to a maximum of two newlines, leading and
      #trailing whitespace removed from each line, and the text
      #optionally wrapped/formatted (if a callback was provided)
      def body_as_text
        text = self.body
        text = Utility.normalize_newlines(text)
        text.gsub!(/\n\n+/, "\n\n")
        text = text.split("\n").map{|line| line.strip }.join("\n")
        if block_given?
          text = text.split("\n\n").map{|line| wrap_text(line){|formatter| yield(formatter) }.chomp }.join("\n\n")
        end
        text
      end
      alias :to_s :body_as_text
      alias :to_str :body_as_text

      #Returns the body, presumed to be raw text, as HTML. Any HTML
      #tags in the body are escaped. Text blocks separated by double
      #newlines are converted to HTML paragraphs, while single
      #newlines are converted to HTML BR tags. Newlines are normalized
      #as in body_as_text, and lines in the HTML source are
      #automatically wrapped using the default Text::Format options,
      #except without any indentation.
      def body_as_html
        text = body_as_text
        text = CGI::escapeHTML(text)
        text = Utility.newlines_to_html(text)
        text = text.split("\n").map do |line| 
          wrap_text(line){|formatter| formatter.first_indent = 0 }.chomp
        end.join("\n") 
        text
      end

      protected

      def wrap_text(text)
        formatter = Text::Format.new
        yield(formatter) if block_given?
        formatter.format(text)
      end

    end #Chunk 
  end #Transcript 
end #Typingpool
