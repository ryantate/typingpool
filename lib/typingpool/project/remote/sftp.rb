module Typingpool
  class Project
    class Remote

      #Subclass for storing remote files on an SFTP server. Only
      #public/private key authentication has been tested. There is not
      #yet any provision for password-based authentication, though
      #adding it should be trivial.
      class SFTP < Remote
        require 'net/sftp'

        #Returns the remote host (server) name. This is set from
        #Config#sftp#host.
        attr_reader :host

        #Returns the remote path (directory). This is set from
        #Config#sftp#path.
        attr_reader :path

        #Returns the name of the user used to log in to the SFTP
        #server. This is et from Config#sftp#user.
        attr_reader :user

        #Returns the base URL, which is prepended to the remote
        #files. This is set from Config#sftp#url.
        attr_reader :url

        #Constructor. Takes the project name and a Config#sftp.
        def initialize(name, sftp_config)
          @name = name
          @config = sftp_config   
          @user = @config.user or raise Error::File::Remote::SFTP, "No SFTP user specified in config"
          @host = @config.host or raise Error::File::Remote::SFTP, "No SFTP host specified in config"
          @url = @config.url or raise Error::File::Remote::SFTP, "No SFTP url specified in config"
          @path = @config.path || ''
        end

        #See docs for Project::Remote::S3#put.
        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          begin
            i = 0
            batch(io_streams) do |stream, connection|
              dest = as[i]
              i += 1
              yield(stream, dest) if block_given?
              connection.upload(stream, join_with_path(dest))
              file_to_url(dest)
            end
          rescue Net::SFTP::StatusException => e
            raise Error::File::Remote::SFTP, "SFTP upload failed: #{e.description}"
          end
        end

        #See docs for Project::Remote::S3#remove.
        def remove(files)
          requests = batch(files) do |file, connection|
            yield(file) if block_given?
            connection.remove(join_with_path(file))
          end
          failures = requests.reject{|request| request.response.ok?}
          if not(failures.empty?)
            summary = failures.map{|request| request.response.to_s}.join('; ')
            raise Error::File::Remote::SFTP, "SFTP removal failed: #{summary}"
          end
        end

        protected

        def connection
          begin
            Net::SFTP.start(@host, @user) do |connection|
              yield(connection)
              connection.loop
            end
          rescue Net::SSH::AuthenticationFailed
            raise Error::File::Remote::SFTP, "SFTP authentication failed: #{$?}"
          end
        end

        def batch(files)
          results = []
          connection do |connection|
            files.each do |file|
              results.push(yield(file, connection))
            end
          end
          return results
        end

        def join_with_path(file)
          if @path
            [@path, file].join('/')
          else
            file
          end
        end
      end #SFTP
    end #Remote
  end #Project
end #Typingpool
