module Typingpool
  class Project
    #Representation of the Project instance in the local
    #filesystem. Subclass of Filer::Dir; see Filer::Dir docs for
    #additional details.
    #
    #This is basically a local dir with various subdirs and files
    #containing the canonical representation of the project, including
    #data on remote resources, the project ID and subtitle, the audio files
    #themselves, and, when complete, an HTML transcript of that audio,
    #along with supporting CSS and Javascript files.
    class Local < Filer::Dir
      require 'fileutils'
      require 'securerandom'

      #Returns the dir path.
      attr_reader :path

      class << self
        #Constructor. Creates a directory in the filesystem for the
        #project.
        #
        # ==== Params
        # [name]         Name of the associated project.
        # [base_dir]     Path to the local directory into which the project
        #                dir should be placed.
        # [template_dir] Path to the dir which will be used as a base
        #                template for new projects.
        # ==== Returns
        # Project::Local instance.
        def create(name, base_dir, template_dir)
          local = super(File.join(base_dir, name))
          FileUtils.cp_r(File.join(template_dir, '.'), local)
          local.create_id
          local
        end

        #Takes the name of a project and a path. If there's a
        #directory with a matching name in the given path whose file
        #layout indicates it is a Project::Local instance (see 'ours?'
        #docs), returns a corresponding Project::Local instance.
        def named(string, path)
          match = super
          if match && ours?(match)
            return match
          end
          return
        end

        #Takes a Filer::Dir instance. Returns true or false depending on whether
        #the file layout inside the dir indicates it is a
        #Project::Local instance.
        def ours?(dir)
          File.exists?(dir.subdir('audio')) && File.exists?(dir.subdir('audio', 'originals'))
        end

        #Takes the name of a project and returns true if it is a valid
        #name for a directory in the local filesystem, false if not.
        def valid_name?(name)
          Utility.in_temp_dir do |dir|
            begin
              FileUtils.mkdir(File.join(dir, name))
            rescue Errno::ENOENT
              return false
            end #begin
            return File.exists?(File.join(dir, name))
          end #Utility.in_temp_dir do...
        end

        #Takes one or more symbols. Adds corresponding getter/setter
        #and delete method(s) to Project::Local, which read (getter)
        #and write (setter) and delete corresponding text files in the
        #data directory.
        #
        #So, for example, 'data_file_accessor :name' would allow you
        #to later create the file 'data/foo.txt' in the project dir by
        #calling 'project.local.name = "Foo"', read that same file via
        #'project.local.name', and delete the file via
        #'project.local.delete_name'
        def data_file_accessor(*syms)
          syms.each do |sym|
            define_method(sym) do
              file('data',"#{sym.to_s}.txt").read
            end
            define_method("#{sym.to_s}=".to_sym) do |value|
              file('data',"#{sym.to_s}.txt").write(value)
            end
            define_method("delete_#{sym.to_s}".to_sym) do
              if File.exists? file('data',"#{sym.to_s}.txt")
                File.delete(file('data',"#{sym.to_s}.txt"))
              end
            end
          end
        end
      end #class << self

      #Calling 'subtitle' will read 'data/subtitle.txt'; calling
      #'subtitle=' will write 'data/subtitle.txt'; calling
      #'delete_subtitle' will delete 'data/subtitle.txt'.
      data_file_accessor :subtitle

      #Returns the ID of the project, as stored in 'data/id.txt'.
      def id
        file('data','id.txt').read
      end

      #Creates a file storing the canonical ID of the project in
      #'data/id.txt'. Raises an exception if the file already exists.
      def create_id
        if id 
          raise Error, "id already exists" 
        end
        file('data','id.txt').write(SecureRandom.hex(16))
      end
    end #Local
  end #Project
end #Typingpool
