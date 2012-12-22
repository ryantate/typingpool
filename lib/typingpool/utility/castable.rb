module Typingpool
  module Utility
    module Castable

      #Cast this object instance to a relative class. Call this from
      #super in your own class if you want to pass args to the
      #relative class constructor. All args after the first will be
      #passed to new.
      #
      #A relative class can be a subclass and in some cases a sibling
      #class, parent class, parent sibling class, grandparent class,
      #grandparent sibling class, and so on. A relative class will
      #never be higher up the inheritance tree than the subclasses of
      #the class where Castable was included.
      # ==== Params
      # [sym] Symbol corresponding to relative class to cast into. For
      #        example, Class#as(:audio) will cast into a Class::Audio
      #        and Class#as(:csv) will cast into Class::CSV. Casting
      #        is class insensitive, which means you can't have class
      #        CSV and class Csv. To cast into a related class whose
      #        name is not not directly under that of its parent, you
      #        must either specify the full name,
      #        e.g. Class#as(:foo_bar_baz) to cast to Foo::Bar::Baz,
      #        or a name relative to the parent,
      #        e.g. Class#as(:remote_html), where Class::Remote does
      #        not inherit from Class but Class::Remote::HTML does.
      # ==== Returns
      # New instance of subclass
      def as(sym, *args)
        if klass = self.class.relative_klass(sym.to_s.downcase)
          klass.new(*args)
        else
          raise Error, "Can't find class '#{sym.to_s}' to cast to"
        end #if subklass =...
      end

      def self.included(receiver)
        receiver.extend(ClassMethods)
      end

      module ClassMethods
        def inherited(subklass)
          subklasses[subklass.to_s.split("#{self.name}::").last.downcase.gsub(/::/, '_')] = subklass
        end

        def subklasses
          @subklasses ||= {}
        end

        def subklass(subklass_key)
          subklasses[subklass_key]
        end

        def relative_klass(key)
          if subklasses[key]
            subklasses[key]
          elsif self.superclass.respond_to? :relative_klass
            self.superclass.relative_klass(key)
          end
        end

      end #module ClassMethods
    end #Castable
  end #Utility
end #Typingpool
