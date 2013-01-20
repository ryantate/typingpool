module Typingpool
  class Project
    #Representation of the Project instance on remote servers. This is
    #basically a collection of audio files to be transcribed and HTML
    #files containing instructions and a form for the
    #transcribers. The backend can be Amazon S3 (the default) or an
    #SFTP server. Each backend is encapsulated in its own subclass. A
    #backend subclass must provide a 'put' method, which takes an
    #array of IO streams and an optional array of remote file
    #basenames; a 'remove' method, which takes an array of remote file
    #basenames; and the methods 'host' and 'path', which return the
    #location of the destination server and destination directory,
    #respectively. The method 'url' returns the URL string pre-pended
    #to each file.
    #
    #Thus, there will always be 'put', 'remove', 'host', 'path', and 'url'
    #methods available, in addition to the Project::Remote methods
    #outlined below.
    class Remote
      require 'typingpool/project/remote/s3'
      require 'typingpool/project/remote/sftp'

      #Constructor. Takes a Config
      #instance. Returns a Project::Remote::S3 or
      #Project::Remote::SFTP instance, depending on the particulars of
      #the Config. If there are sufficient config params to return
      #EITHER an S3 or SFTP subclass, it will prefer the SFTP
      #subclass.
      def self.from_config(config)
        if config.sftp
          SFTP.from_config(config.sftp)
        elsif config.amazon && config.amazon.bucket
          S3.from_config(config.amazon)
        else
          raise Error, "No valid upload params found in config file (SFTP or Amazon info)"
        end
      end

      #Like project.remote.remove, except it takes an array of URLs
      #instead an array of remote basenames, saving you from having to
      #manually extract basenames from the URL.
      def remove_urls(urls)
        basenames = urls.map{|url| url_basename(url) } 
        remove(basenames){|file| yield(file) if block_given? }
      end

      #Given a file path, returns the URL to the file path were it to
      #be uploaded by this instance.
      def file_to_url(file)
        "#{url}/#{URI.escape(file)}"
      end

      #Given an URL, returns the file portion of the path, given the
      #configuration of this instance.
      def url_basename(url)
        basename = url.split("#{self.url}/")[1] or raise Error, "Could not find base url '#{self.url}' within longer url '#{url}'"
        URI.unescape(basename)
      end


    end #Remote
  end #Project
end #Typingpool
