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
        look_in =  [File.join(Utility.lib_dir, 'templates'), '']
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
      ['.html.erb', '.erb', '']
    end
    require 'typingpool/template/assignment'
    require 'typingpool/template/env'
  end #Template
end #Typingpool
