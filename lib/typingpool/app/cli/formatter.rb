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
      end #Formatter
    end #CLI
  end #App
end #Typingpool
