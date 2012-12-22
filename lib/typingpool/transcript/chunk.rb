module Typingpool
  class Transcript

    #Transcript::Chunk is the model class for one transcription by one
    #Mechanical Turk worker of one "chunk" (a file) of audio, which in
    #turn is a portion of a larger recording (for example, one minute
    #of a 60 minute interview). It is basically parallel and similar
    #to an Amazon::HIT instance. Transcript is a container for these
    #chunks, which know how to render themselves as text and HTML.
    class Chunk
      require 'cgi'
      require 'rubygems/text'
      include Gem::Text

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

      #Takes an optional specification of how many spaces to indent
      #the text by (default 0) and an optional specification of how
      #many characters to wrap at (default no wrapping).
      #
      #Returns the text with newlines normalized to Unix format, runs
      #of newlines shortened to a maximum of two newlines, leading and
      #trailing whitespace removed from each line, and the text
      #wrapped/indented as specified.
      def body_as_text(indent=nil, wrap=nil)
        text = self.body
        text = Utility.normalize_newlines(text)
        text.gsub!(/\n\n+/, "\n\n")
        text = text.split("\n").map{|line| line.strip }.join("\n")
        text = wrap_text(text, wrap) if wrap
        text = indent_text(text, indent) if indent
        text
      end
      alias :to_s :body_as_text
      alias :to_str :body_as_text

      #Takes an optional count of how many characters to wrap at
      #(default 72). Returns the body, presumed to be raw text, as
      #HTML. Any HTML tags in the body are escaped. Text blocks
      #separated by double newlines are converted to HTML paragraphs,
      #while single newlines are converted to HTML BR tags. Newlines
      #are normalized as in body_as_text, and lines in the HTML source
      #are automatically wrapped as specified.
      def body_as_html(wrap=72)
        text = body_as_text
        text = CGI::escapeHTML(text)
        text = Utility.newlines_to_html(text)
        text = text.split("\n").map do |line| 
          wrap_text(line, 72).chomp
        end.join("\n") 
        text
      end

      protected

      def indent_text(text, indent)
        text.gsub!(/^/, " " * indent)
        text
      end

      def wrap_text(text, wrap=72)
        format_text(text, wrap)
      end
    end #Chunk 
  end #Transcript 
end #Typingpool
