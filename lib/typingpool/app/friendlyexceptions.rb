module Typingpool
  module App
    module FriendlyExceptions

      #Massages terse exceptions from our model layer into a
      #human-friendly message suitable for an abort message from a
      #command-line script.
      # ==== Params
      # [name]   A string used to refer to the input. For example
      #          'project title' or '--config argument'. Used in the
      #          goodbye message.
      # [*input] One or more values. The user input that will cause
      #          any exceptions. Used in the goodbye message.
      # [&block] The block to execute and monitor for
      #          exceptions. Will be passed [*input].
      # ==== Errors
      # Will abort with a friendly message on any exception of the
      # type Typingpool::Error::Argument.
      # ==== Returns
      # The return value of &block.
      def with_friendly_exceptions(name, *input)
        begin
          yield(*input)
        rescue Typingpool::Error::Argument => exception
          goodbye = "Could not make sense of #{name.to_s} "
          goodbye += input.map{|input| "'#{input}'" }.join(', ')
          goodbye += ". #{exception.message}"
          goodbye += '.' unless goodbye.match(/\.$/)
          abort goodbye
        end #begin
      end
    end #FriendlyExceptions
  end #App
end #Typingpool
