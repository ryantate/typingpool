module Typingpool
  class Filer

    #Convenience wrapper for audio files.You can convert to mp3s,
    #split into multiple files, and dynamically read the bitrate.
    class Audio < Filer
      require 'open3'

      #Does the file have a '.mp3' extension?
      def mp3?
        File.extname(@path).downcase.eql?('.mp3')
      end

      #Convert to mp3 via ffmpeg. 
      # ==== Params
      # [dest]    Filer object corresponding to the path the mp3 version
      #           should end up at.
      # [bitrate] If passed, bitrate should be an integer
      #           corresponding to kb/s. If not, we use the bitrate
      #           from the current file or, if that can't be read,
      #           default to 192kbps. Does not check if the file is
      #           already an mp3. Returns a new Filer::Audio
      #           representing the new mp3 file.
      # ==== Returns
      # Filer::Audio containing the new mp3.
      def to_mp3(dest=self.dir.file("#{File.basename(@path, '.*') }.mp3"), bitrate=nil)
        bitrate ||= self.bitrate || 192
        Utility.system_quietly('ffmpeg', '-i', @path, '-acodec', 'libmp3lame', '-ab', "#{bitrate}k", '-ac', '2', dest)
        File.exists?(dest) or raise Error::Shell, "Could not found output from `ffmpeg` on #{path}"
        self.class.new(dest.path)
      end

      #Reads the bitrate of the audio file via ffmpeg. Returns an
      #integer corresponding to kb/s, or nil if the bitrate could not
      #be determined.
      def bitrate
        out, err, status = Open3.capture3('ffmpeg', '-i', @path)
        bitrate = err.match(/(\d+) kb\/s/)
        return bitrate ? bitrate[1].to_i : nil
      end

      #Splits an mp3 into smaller files. 
      # ==== Params
      # [interval_in_min_dot_seconds] Split the file into chunks this
      #             large. The interval should be of the format
      #             minute.seconds, for example 2 minutes 15 seconds
      #             would be written as "2.15". For further details on
      #             interval format, consult the documentation for
      #             mp3split, a command-line unix utility.
      # [basename]  Name the new chunks using this base. Default is the
      #             basename of the original file.
      # [dest]      Destination directory for the new chunks as a
      #             Filer::Dir. Default is the same directory as the
      #             original file.
      # ==== Returns
      # Filer::Files containing the new files.
      def split(interval_in_min_dot_seconds, basename=File.basename(path, '.*'), dest=dir)
        #We have to cd into the wrapfile directory and do everything
        #there because old/packaged versions of mp3splt were
        #retarded at handling absolute directory paths
        ::Dir.chdir(dir.path) do
          Utility.system_quietly('mp3splt', '-t', interval_in_min_dot_seconds, '-o', "#{basename}.@m.@s", File.basename(path)) 
        end
        files = Filer::Files::Audio.new(dir.select{|file| File.basename(file.path).match(/^#{Regexp.escape(basename) }\.\d+\.\d+\.mp3$/) })
        if files.to_a.empty?
          raise Error::Shell, "Could not find output from `mp3splt` on #{path}"
        end
        if dest.path != dir.path
          files.mv!(dest)
        end
        files.sort
      end

      #Extracts from the filename the offset time of the chunk
      #relative to the original from which it was split. Format is
      #minute.seconds. Suitable for use on files created by 'split'
      #method.
      def offset
        match = File.basename(@path).match(/\d+\.\d\d\b/)
        return match[0] if match
      end
    end #Audio
  end #Filer
end #Typingpool
