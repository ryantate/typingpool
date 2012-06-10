module Typingpool
  class Transcript
    include Enumerable
    require 'csv'
    attr_accessor :title, :subtitle, :url

    def initialize(title=nil, chunks=[])
      @title = title
      @chunks = chunks
    end

    def each
      @chunks.each do |chunk|
        yield chunk
      end
    end

    def [](index)
      @chunks[index]
    end

    def to_s
      @chunks.join("\n\n")
    end
    
    def add_chunk(chunk)
      @chunks.push(chunk)
    end

    class Chunk
      require 'cgi'
      require 'text/format'

      attr_accessor :body, :worker, :hit, :project
      attr_reader :offset, :offset_seconds, :filename, :filename_local

      def initialize(body)
        @body = body
      end

      def <=>(other)
        self.offset_seconds <=> other.offset_seconds
      end

      def url=(url)
        #http://ryantate.com/transfer/Speech.01.00.ede9b0f2aed0d35a26cef7160bc9e35e.ISEAOM.mp3
        matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
        @url = matches[0]
        @filename = matches[1]
        @filename_local = Project.local_basename_from_url(@url)
        @offset = "#{matches[3]}:#{matches[4]}"
        @offset_seconds = (matches[3].to_i * 60) + matches[4].to_i
      end

      def url
        @url
      end

      def wrap_text(text)
        formatter = Text::Format.new
        yield(formatter) if block_given?
        formatter.format(text)
      end

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

      def body_as_html
        text = body_as_text
        text = CGI::escapeHTML(text)
        text = Utility.newlines_to_html(text)
        text = text.split("\n").map do |line| 
          wrap_text(line){|formatter| formatter.first_indent = 0 }.chomp
        end.join("\n") 
        text
      end
    end #Chunk 
  end #Transcript 
end #Typingpool
