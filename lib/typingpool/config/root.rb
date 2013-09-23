module Typingpool
  class Config    

    #The root level of the config file and all full config
    #objects. Kept distinct from Config because other subclasses need
    #to inherit from Config, and we don't want them inheriting the
    #root level fields.
    class Root < Config
      local_path_reader :transcripts, :cache, :templates

      class SFTP < Config
        never_ends_in_slash_reader :path, :url
      end

      class Amazon < Config
        never_ends_in_slash_reader :url
      end

      class Assign < Config
        local_path_reader :templates
        time_accessor :deadline, :approval, :lifetime

        define_accessor(:reward) do |value|
          value.to_s.match(/(\d+(\.\d+)?)|(\d*\.\d+)/) or raise Error::Argument::Format, "Format should be N.NN"
          value
        end

        define_reader(:confirm) do |value|
          next false if value.to_s.match(/(^n)|(^0)|(^false)/i)
          next true if value.to_s.match(/(^y)|(^1)|(^true)/i)
          next if value.to_s.empty?
          raise Error::Argument::Format, "Format should be 'yes' or 'no'"
        end

        def qualify
          self.qualify = (@param['qualify'] || []) unless @qualify
          @qualify
        end

        def qualify=(specs)
          @qualify = specs.map{|spec| Qualification.new(spec) }
        end

        def add_qualification(spec)
          self.qualify.push(Qualification.new(spec))
        end

        def keywords
          @param['keywords'] ||= []
        end

        def keywords=(array)
          @param['keywords'] = array
        end

        class Qualification < Config
          def initialize(spec)
            @raw = spec
            to_arg #make sure value parses
          end

          def to_s
            @raw
          end

          def to_arg
            [type, opts]
          end

          protected

          def type
            type = @raw.split(/\s+/)[0]
            if RTurk::Qualification.types[type.to_sym]
              return type.to_sym
            elsif (type.match(/\d/) || type.size >= 25)
              return type
            else
              #Seems likely to be qualification typo: Not a known
              #system qualification, all letters and less than 25
              #chars
              raise Error::Argument, "Unknown qualification type and does not appear to be a raw qualification type ID: '#{type.to_s}'"
            end 
          end

          def opts
            args = @raw.split(/\s+/)
            if (args.count > 3) || (args.count < 2)
              raise Error::Argument, "Unexpected number of qualification tokens: #{@raw}"
            end
            args.shift
            comparator(args[0]) or raise Error::Argument, "Unknown comparator '#{args[0]}'"
            value = 1
            value = args[1] if args.count == 2
            return {comparator(args[0]) => value}
          end

          def comparator(value)
            Hash[
                 '>' => :gt,
                 '>=' => :gte,
                 '<' => :lt,
                 '<=' => :lte,
                 '==' => :eql,
                 '!=' => :not,
                 'true' => :eql,
                 'exists' => :exists
                ][value]
          end
        end #Qualification
      end #Assign
    end #Root
  end #Config
end #Typingpool
