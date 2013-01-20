module Typingpool
  class Project
    class Remote

      #Subclass for storing remote files on Amazon Simple Storage
      #Service (S3)
      class S3 < Remote
        require 'aws-sdk'

        #Takes a Config#amazon, extracts the needed params, and
        #returns a Project::Remote::S3 instance. Raises an exception
        #of type Error::File::Remote::S3 if any required params (key,
        #secret, bucket) are missing from the config.
        def self.from_config(config_amazon)
          key = config_amazon.key or raise Error::File::Remote::S3, "Missing Amazon key in config"
          secret = config_amazon.secret or raise Error::File::Remote::S3, "Missing Amazon secret in config"
          bucket_name = config_amazon.bucket or raise Error::File::Remote::S3, "Missing Amazon bucket in config"
          url = config_amazon.url
          new(key, secret, bucket_name, url)
        end

        #Takes an optional length for the random sequence, 16 by
        #default, and an optional bucket name prefix, 'typingpool-' by
        #default. Returns a string safe for use as both an S3 bucket
        #and as a subdomain. Random charcters are drawn from [a-z0-9],
        #though the first character in the returned string will always
        #be a letter.
        def self.random_bucket_name(length=16, prefix='typingpool-')
          charset = [(0 .. 9).to_a, ('a' .. 'z').to_a].flatten
          if prefix.to_s.empty? && (length > 0)
            #ensure subdomain starts with a letter
            prefix = ('a' .. 'z').to_a[SecureRandom.random_number(26)]
            length -= 1
          end
          random_sequence = (1 .. length).map{ charset[ SecureRandom.random_number(charset.count) ] }
          [prefix.to_s, random_sequence].join
        end

        #Returns the base URL, which is prepended to the remote
        #files. This is either the 'url' attribute of the
        #Config#amazon value passed to Project::Remote::S3.new or, if
        #that attribute is not set, the value returned by
        #'default_url' (e.g. "https://bucketname.s3.amazonaws.com").
        attr_reader :url

        #Constructor. Takes an Amazon AWS access key id, secret access
        #key, bucket name, and optional URL prefix.
        def initialize(key, secret, bucket, url=nil)
          @key = key 
          @secret = secret
          @bucket_name = bucket 
          @url = url || default_url
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
        #             or StringIO instance. Each IO object must repond
        #             to the methods rewind, read, and eof? (so no
        #             pipes, sockets, etc)
        #[as]         Optional if the io_streams are File instances. Array of
        #             file basenames, used to name the destination
        #             files. Default is the basename of the Files
        #             passed in as io_streams.
        #[&block]     Optional. Passed an io_stream and destination name
        #             just before each upload
        # ==== Returns
        #Array of URLs corresponding to the uploaded files.
        def put(io_streams, as=io_streams.map{|file| File.basename(file)})
          batch(io_streams) do |stream, i|
            dest = as[i]
            yield(stream, dest) if block_given?
            begin
              s3.buckets[@bucket_name].objects[dest].write(stream, :acl => :public_read)
            rescue AWS::S3::Errors::NoSuchBucket
              s3.buckets.create(@bucket_name, :acl => :public_read)
              stream.rewind
              retry
            end #begin
            file_to_url(dest)
          end #batch
        end

        #Delete objects from S3.
        # ==== Params
        #[files]  Enumerable collection of file names. Should NOT
        #         include the bucket name (path).
        #[&block] Optional. Passed a file name before each delete.
        # ==== Returns
        #Nil
        def remove(files)
          batch(files) do |file, i|
            yield(file) if block_given?
            s3.buckets[@bucket_name].objects[file].delete
          end
          nil
        end

        protected

        def batch(io_streams)
          results = []
          io_streams.each_with_index do |stream, i|
            begin
              results.push(yield(stream, i))
            rescue AWS::S3::Errors::InvalidAccessKeyId
              raise Error::File::Remote::S3::Credentials, "S3 operation failed because your AWS access key ID  is wrong. Double-check your config file."
            rescue AWS::S3::Errors::SignatureDoesNotMatch
              raise Error::File::Remote::S3::Credentials, "S3 operation failed with a signature error. This likely means your AWS secret access key is wrong."
            rescue AWS::Errors::Base => e
              raise Error::File::Remote::S3, "Your S3 operation failed with an Amazon error: #{e} (#{e.class})"
            end #begin
          end #io_streams.each_with_index
          results
        end

        def s3
          AWS::S3.new(
                     :access_key_id => @key,
                     :secret_access_key => @secret
                     )
        end

        def default_url
          "https://#{@bucket_name}.s3.amazonaws.com"
        end
      end #S3
    end #Remote
  end #Project
end #Typingpool
