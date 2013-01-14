module Typingpool
  class Project
    class Remote

      #Subclass for storing remote files on Amazon Simple Storage
      #Service (S3)
      class S3 < Remote
        require 'aws/s3'

        #An Amazon Web Services "Access Key ID." Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :key

        #An Amazon Web Services "Secret Access Key." Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :secret

        #The S3 "bucket" where uploads will be stores. Set from the
        #Config#amazon value passed to Project::Remote::S3.new, but
        #changeable.
        attr_accessor :bucket

        #Returns the base URL, which is prepended to the remote
        #files. This is either the 'url' attribute of the
        #Config#amazon value passed to Project::Remote::S3.new or, if
        #that attribute is not set, the value returned by
        #'default_url' (e.g. "https://bucketname.s3.amazonaws.com").
        attr_reader :url

        #Constructor. Takes the project name and the result of calling
        #the 'amazon' method on a Config instance (i.e. the amazon
        #section of a Config file).
        def initialize(name, amazon_config)
          @name = name
          @config = amazon_config
          @key = @config.key or raise Error::File::Remote::S3, "Missing Amazon key in config"
          @secret = @config.secret or raise Error::File::Remote::S3, "Missing Amazon secret in config"
          @bucket = @config.bucket or raise Error::File::Remote::S3, "Missing Amazon bucket in config"
          @url = @config.url || default_url
        end

        #The remote host (server) name, parsed from #url
        def host
          URI.parse(@url).host
        end

        #The remote path (directory), pased from #url
        def path
          URI.parse(@url).path
        end

        #Upload files/strings to S3, optionally changing the names in the process.
        # ==== Params
        #[io_streams] Enumerable collection of IO objects, like a File
        #             or StringIO instance.
        #[as]         Optional if the io_streams are File instances. Array of
        #             file basenames, used to name the destination
        #             files. Default is the basename of the Files
        #             passed in as io_streams.
        # ==== Returns
        #Array of URLs corresponding to the uploaded files.
        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          batch(io_streams) do |stream, i|
            dest = as[i]
            yield(stream, dest) if block_given?
            begin
              AWS::S3::S3Object.store(dest, stream, @bucket,  :access => :public_read)
            rescue AWS::S3::NoSuchBucket
              make_bucket
              retry
            end
            file_to_url(dest)
          end #batch
        end

        #Delete objects from S3.
        # ==== Params
        #[files] Enumerable collection of file names. Should NOT
        #        include the bucket name (path).
        # ==== Returns
        #Array of booleans corresponding to whether the delete call
        #succeeded.
        def remove(files)
          batch(files) do |file, i|
            yield(file) if block_given?
            AWS::S3::S3Object.delete(file, @bucket)
          end
        end

        protected

        def batch(io_streams)
          results = []
          io_streams.each_with_index do |stream, i|
            connect if i == 0
            begin
              results.push(yield(stream, i))
            rescue AWS::S3::S3Exception => e
              if e.message.match(/AWS::S3::SignatureDoesNotMatch/)
                raise Error::File::Remote::S3::Credentials, "S3 operation failed with a signature error. This likely means your AWS key or secret is wrong. Error: #{e}"
              else
                raise Error::File::Remote::S3, "Your S3 operation failed with an Amazon error: #{e}"
              end #if    
            end #begin
          end #files.each
          disconnect unless io_streams.empty?
          results
        end

        def connect
          AWS::S3::Base.establish_connection!(
                                              :access_key_id => @key,
                                              :secret_access_key => @secret,
                                              :persistent => false,
                                              :use_ssl => true
                                              )
        end

        def disconnect
          AWS::S3::Base.disconnect
        end

        def make_bucket
          AWS::S3::Bucket.create(@bucket)
        end

        def default_url
          "https://#{@bucket}.s3.amazonaws.com"
        end
      end #S3
    end #Remote
  end #Project
end #Typingpool
