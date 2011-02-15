module Audibleturk
  def self.config_file
    loc = "#{ENV['HOME']}/.audibleturk"
    file = IO.read(loc) or abort "Could not find config file at #{loc}"
  end

  class Transcription
    include Enumerable
    require 'csv'
    attr_accessor :title, :notes

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
    
    def self.from_csv(csv_string)
      transcription = Audibleturk::Transcription.new
      CSV.parse(csv_string) do |row|
        next if row[16] != 'Approved'                            
        chunk = Audibleturk::Transcription::Chunk.from_csv(row)
        transcription.add_chunk(chunk)
        transcription.csv_url = row[25] unless transcription.title
      end
      return transcription
    end

    def csv_url=(url)
      @title = /.+\/(\w+)\.[^\/]+$/.match(url)[1] or raise "Unexpected format to url '#{url}'"
    end

    def add_chunk(chunk)
      @chunks.push(chunk)
    end

    class Chunk
      require 'text/format'
      require 'cgi'

      attr_accessor :body, :worker
      attr_reader :offset_start, :offset_start_seconds, :filename

      def initialize(body)
        @body = body
      end

      def <=>(other)
        self.offset_start_seconds <=> other.offset_start_seconds
      end

      def self.from_csv(row)
        chunk = Chunk.new(row[26])
        chunk.worker = row[15]
        chunk.url = row[25]
        return chunk
      end

      def url=(url)
        #http://ryantate.com/transfer/Speech.00.00-01.00.mp3
        matches = /.+\/([\w\/\-]+\.(\d+)\.(\d\d)\.[^\/\.]+)$/.match(url) or raise "Unexpected format to url '#{url}'"
        @url = matches[0]
        @filename = matches[1]
        @offset_start = "#{matches[2]}:#{matches[3]}"
        @offset_start_seconds = (matches[2].to_i * 60) + matches[3].to_i
      end

      def url
        @url
      end

      def body_as_wrapped_text
        wrap_text(self.body)
      end

      def wrap_text(text)
        formatter = Text::Format.new
        formatter.first_indent = 0
        formatter.format(text)
      end

      def body_as_html
        text = self.body
        text = CGI::escapeHTML(text)
        text.gsub!("\r\n", "\n")
        text.gsub!("\r", "\n")
        text.gsub!("\f", "\n")
        text.gsub!(/\n\n+/, '<p>')
        text.gsub!("\n", '<br>')
        text.gsub!('<p>', "\n\n<p>")
        text.gsub!('<br>', "\n<br>")
        text.gsub!(/\A\s+/, '')
        text.gsub!(/\s+\z/, '')
        text = text.split("\n").collect {|line| wrap_text(line) }.join("\n") 
        text.gsub!(/\n\n+/, "\n\n")
      end
    end
  end
end
