module Typingpool
  class Template

    #This subclass provides two utility methods to all templates:
    #read, for including the text of another template, and render, for
    #rendering another template. Read takes a relative path,
    #documented below. Render is passed the same hash as the parent
    #template, merged with an optional override hash, as documented
    #below.
    #
    #This subclass also makes it easier to use a hash as the top-level
    #variable namespace when rendering ERB templates.
    class Env

      #Construtor. Takes a hash to be passed to the template and a
      #template (ERB).
      def initialize(hash, template)
        @hash = hash
        @template = template
      end

      #Method passed into each template. Takes a relative path and
      #returns the text of the file at that path.
      #
      #The relative path is resolved as in look_in above, with the
      #following difference: the current directory and each parent
      #directory of the active template is searched first, up to the
      #root transcript directory (either Config#template, the built-in
      #app template dir, or any dir that has been manually added to
      #look_in).
      def read(path)
        @template.class.new(path, localized_look_in).read.strip
      end

      #Method passed into each template. Takes a reltive path and
      #returns the *rendered* text of the ERB template at that
      #path. Can also take an optional hash, which will be merged into
      #the parent template's hash and passed to the included
      #template. If the optional hash it not passed, the parent
      #template's hash will be passed to the included template
      #unmodified.
      #
      #The relative path is resolved as described in the docs for
      #Template::Env#read.
      def render(path, hash={})
        @template.class.new(path, localized_look_in).render(@hash.merge(hash)).strip
      end

      def get_binding
        binding()
      end

      protected

      def localized_look_in
        look_in = []
        path = @template.full_path
        until @template.look_in.include? path = File.dirname(path)
          look_in.push(path)
        end
        look_in.push(path, (@template.look_in - [path])).flatten
      end

      def method_missing(key, value=nil)
        if value
          key = key.to_s.sub(/=$/, '')
          @hash[key.to_sym] = value
        end
        if @hash.has_key? key
          @hash[key]
        elsif @hash.has_key? key.to_s
          @hash[key.to_s]
        end
      end
    end #Env
  end #Template
end #Typingpool
