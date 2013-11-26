module Typingpool
  module App
    module CLI
      module Formatter
        require 'highline/import'
        def cli_bold(text)
          HighLine.color(text, :bold)
        end

        def cli_reverse(text)
          HighLine.color(text, :reverse)
        end

        def cli_encode(text)
          unless (text.encoding.to_s == Encoding.default_external.to_s)
            text.encode!(Encoding.default_external, :invalid => :replace, :undef => :replace, :replace => "?")
          end
          text
        end
      end #Formatter
    end #CLI
  end #App
end #Typingpool
