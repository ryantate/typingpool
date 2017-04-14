module Typingpool
  module App
    module CLI
      module Formatter
        require 'highline/import'

        def prompt_from_choices(choices, default_index)
          prompt = choices.map do |choice| 
            cli_reverse('(') +
              cli_reverse(cli_bold(choice.slice(0).upcase)) +
              cli_reverse(")#{choice.slice(1, choice.size)}") 
          end
          prompt[default_index] =  cli_reverse('[') + prompt[default_index] + cli_reverse(']')
          prompt = prompt.join(cli_reverse(', ')) 
          prompt
        end

        def ask_for_selection(choices, default_index, prompt)
          selection = nil
          until selection
            input = ask(prompt)
            if input.to_s.match(/^\s*$/)
              selection = choices.last
            elsif not(selection = choices.detect{|possible| possible[0] == input.downcase[0] })
              say("Invalid selection '#{input}'.")
            end
          end #until selection
          selection
        end
        
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
