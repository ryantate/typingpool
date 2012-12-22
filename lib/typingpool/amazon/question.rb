module Typingpool
  class Amazon

    #Class encapsulating the HTML form presented to Mechanical Turk workers
    #transcribing a Typingpool audio chunk.
    class Question
      require 'nokogiri'
      require 'uri'
      require 'cgi'
      attr_reader :url, :html

      #Constructor. Takes the URL of where the question HTML has been
      #uploaded, followed by the question HTML itself.
      def initialize(url, html)
        @url = url
        @html = html
      end

      #Returns URL-encoded key-value pairs that can be used as the
      #text for a HIT#annotation. The key-value pairs correspond to
      #all hidden HTML form fields in the question HTML.
      def annotation
        CGI.escapeHTML(URI.encode_www_form(Hash[*noko.css('input[type="hidden"]').select{|e| e['name'].match(/^typingpool_/) }.map{|e| [e['name'], e['value']]}.flatten]))
      end

      #Returns the title, extracted from the title element of the
      #HTML.
      def title
        noko.css('title')[0].content
      end

      #Returns the description, extracted from the element with the id
      #'description' in the HTML.
      def description
        noko.css('#description')[0].content
      end

      protected

      def noko(html=@html)
        Nokogiri::HTML(html, nil, 'UTF-8')
      end
    end #Question
  end #Amazon
end #Typingpool
