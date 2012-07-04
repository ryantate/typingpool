module Typingpool
  #Model class that wraps ERB and adds a few Typingpool-specific
  #capabilities: The ability to look in an array of search paths for a
  #particular relative path, neccesary to support the Config#template
  #dir on top of the built-in app template dir. Also makes it easy to
  #pass in a hash and render the template against that hash, rather
  #than against all the variables in the current namespace.
  class Template
    require 'erb'
    class << self
      #Constructor. Takes a relative template path and an optional
      #config file. Default config is Config.file.
      def from_config(path, config=Config.file)
        validate_config(config)
        new(path, look_in_from_config(config))
      end

      #private

      def look_in_from_config(config)
        look_in =  [File.join(config.app, 'templates'), '']
        look_in.unshift(config.templates) if config.templates
        look_in
      end

      def validate_config(config)
        if config.templates
          File.exists?(config.templates) or raise Error::File::NotExists, "No such templates dir: #{config.templates}"
          File.directory?(config.templates) or raise Error::File::NotExists, "Templates dir not a directory: #{config.templates}"
        end
      end
    end #class << self

    #An array of base paths to be searched when we're given a relative
    #path to the template. Normally this includes the user's
    #Config#template attribute, if any, followed by the built-in app
    #template dir.
    attr_reader :look_in

    #Constructor. Takes a relative path and an array of base paths to
    #search for relative template paths. See look_in docs. Template
    #should be an ERB template.
    def initialize(path, look_in)
      @path = path
      @look_in = look_in
      full_path or raise Error, "Could not find template path '#{path}' in #{look_in.join(',')}"
    end

    #Takes a hash to pass to an ERB template and returns the text from
    #rendering the template against that hash (the hash becomes the
    #top-level namespace of the template, so the keys are accessed
    #just as you'd normally access a variable in an ERB template).
    def render(hash)
      render_with_binding(Env.new(hash, self).get_binding)
    end

    #Like render, but takes a binding instead of hash
    def render_with_binding(binding)
      ERB.new(read, nil, '<>').result(binding)
    end

    #Returns the raw text of the template, unrendered.
    def read
      IO.read(full_path)
    end

    #Returns the path to the template after searching the various
    #look_in dirs for the relative path. Returns nil if the template
    #cannot be located.
    def full_path
      look_in.each do |dir|
        extensions.each do |ext| 
          path = File.join(dir, [@path, ext].join)
          if File.exists?(path) && File.file?(path)
            return path
          end
        end
      end
      return
    end

    protected

    def extensions
      ['.html.erb', '']
    end


    #A Template::Assignment works just like a regular template, except
    #that within each transcript dir (Config#transcript and the
    #built-in app template dir) we search within a subdir called
    #'assignment' first, then, after all the 'assignment' subdirs have
    #been search, we look in the original template dirs.
    class Assignment < Template
      def self.look_in_from_config(*args)
        look_in = super(*args)
        look_in.unshift(look_in.reject{|dir| dir.empty? }.map{|dir| File.join(dir, 'assignment') })
        look_in.flatten
      end
    end #Assignment

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
        original = @hash
        @hash = @hash.merge(hash)
        rendered = @template.class.new(path, localized_look_in).render_with_binding(binding).strip
        @hash = original
        rendered
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
          @hash[key] = value
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
