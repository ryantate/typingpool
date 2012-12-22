module Typingpool
  class Filer
    class Files

      #Handler for collection of Filer::Audio instances. Does
      #everything Filer::Files does, plus can batch convert to mp3 an
      #can merge the Filer::Audio instances into a single audio file,
      #provided they are in mp3 format.
      class Audio < Files

        #Constructor. Takes an array of Filer or Filer subclass instances.
        def initialize(files)
          @files = files.map{|file| self.file(file.path) }
        end

        def file(path)
          Filer::Audio.new(path)
        end

        #Batch convert Filer::Audio instances to mp3 format.
        # ==== Params
        # [dest_dir] Filer::Dir instance corresponding to directory
        #            into which mp3 file versions will be created.
        # [bitrate]  See documentation for Filer::Audio#bitrate.
        # ==== Returns
        # Filer::Files::Audio instance corresponding to new mp3
        # versions of the original files or, in the case where the
        # original file was already in mp3 format, corresponding to
        # the original files themselves.
        def to_mp3(dest_dir, bitrate=nil)
          mp3s = self.map do |file|
            if file.mp3?
              file
            else
              yield(file) if block_given?
              file.to_mp3(dest_dir.file("#{File.basename(file.path, '.*') }.mp3"), bitrate)
            end
          end
          self.class.new(mp3s)
        end

        #Merge Filer::Audio instances into a single new file, provided
        #they are all in mp3 format.
        # ==== Params
        #[into_file] Filer or Filer subclass instance corresponding to
        #the location of the new, merged file that should be created.
        # ==== Returns
        # Filer::Audio instance corresponding to the new, merged file.
        def merge(into_file)
          raise Error::Argument, "No files to merge" if self.to_a.empty?
          if self.count > 1
            Utility.system_quietly('mp3wrap', into_file, *self.to_a)
            written = File.join(into_file.dir, "#{File.basename(into_file.path, '.*') }_MP3WRAP.mp3")
            FileUtils.mv(written, into_file)
          else
            FileUtils.cp(self.first, into_file)
          end
          self.file(into_file.path)
        end
      end #Audio
    end #Files
  end #Filer
end #Typingpool
