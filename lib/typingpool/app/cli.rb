module Typingpool
  module App
    module CLI
      class << self
        include App::FriendlyExceptions

        #Optionally takes an ostensible path to a config file, as passed
        #as a command-line option. Checks to make sure the file exists;
        #returns nil if does not, returns a Config instance if it
        #does. If no path is passed, the default config file is returned
        #(as retrieved by Config.file with no args).
        def config_from_arg(arg=nil)
          if arg
            path = File.expand_path(arg)
            return unless File.exists?(path) && File.file?(path)
            Config.file(path)
          else
            Config.file
          end #if option
        end

        #Outputs a friendly explanation of the --help option for
        #appending to script usage banners.
        def help_arg_explanation
          "`#{File.basename($PROGRAM_NAME)} --help` for more information."
        end

        #Converts a user arg into a Project instance, setting up or
        #consulting a Config along the way.
        # ==== Params
        # [arg]    A user-supplied argument specifying either an absolute
        #          path to a Project folder (Project#local) or the
        #          name of a project folder within
        #          [config]#transcripts.
        # [config] A Config instance. If [arg] is an absolute path,
        #          will be modified -- Config#itranscripts will be
        #          changed to match the implied transcripts dir.
        # ==== Errors
        # Will abort with a friendly message on any errors.
        # ==== Returns
        # A Project instance.
        def project_from_arg_and_config(arg, config)
          path = if (File.exists?(arg) && File.directory?(arg))
                   config.transcripts = File.dirname(arg)
                   arg
                 else
                   abort "No 'transcripts' dir specified in your config file and '#{arg}' is not a valid path" unless config.transcripts
                   path = File.join(config.transcripts, arg)
                   abort "No such project '#{arg}' in dir '#{config.transcripts}'" unless File.exists? path
                   abort "'#{arg}' is not a directory at '#{path}'" unless File.directory? path
                   path
                 end
          project = with_friendly_exceptions('project name', File.basename(path)) do 
            Typingpool::Project.new(File.basename(path), config)
          end
          abort "Not a project directory at '#{path}'" unless project.local
          project
        end

      end #class << self
      require 'typingpool/app/cli/formatter'
    end #CLI
  end #App
end #Typingpool
