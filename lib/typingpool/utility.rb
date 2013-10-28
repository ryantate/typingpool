module Typingpool
  module Utility
    require 'open3'
    require 'uri'
    require 'tmpdir'
    require 'set'
    require 'net/http'

    class << self
      #Much like Kernel#system, except it doesn't spew STDERR and
      #STDOUT all over your screen (when called with multiple args,
      #which with Kernel#systems kills the chance to do shell style
      #stream redirects like 2>/dev/null). Even more like
      #Open3.capture3, except it raises an exception on unsuccesful
      #exit status.
      #
      # ==== Params
      #[cmd] Commands to send to the shell, just as with Kernel#system.
      #
      # ==== Returns
      #On success: STDOUT, or true if STDOUT is empty
      #On failure: Raises Typingpool::Error::Shell, with STDERR as
      #error text if available.
      def system_quietly(*cmd)
        out, err, status = Open3.capture3(*cmd)
        if status.success?
          return out ? out.chomp : true
        else
          if err
            raise Error::Shell, err.chomp
          else
            raise Error::Shell
          end
        end
      end

      #Convert config entries like '30s','2d','10h'. etc into number of seconds.
      #
      # ==== Params
      #[timespec] string conforming to format outlined at
      #http://search.cpan.org/~markstos/CGI-Session-4.48/lib/CGI/Session.pm#expire($param,_$time)
      # ==== Returns
      #Number of whole seconds corresponding to the timespec. Raises
      #Typingpool::Error::Argument::Format on bad input.
      def timespec_to_seconds(timespec)
        timespec or return
        suffix_to_time = {
          's'=>1,
          'm'=>60,
          'h'=>60*60,
          'd'=>60*60*24,
          'M'=>60*60*24*30,
          'y'=>60*60*24*365
        }
        match = timespec.to_s.match(/^\+?(\d+(\.\d+)?)\s*([#{suffix_to_time.keys.join}])?$/) or raise Error::Argument::Format, "Can't convert '#{timespec}' to time"
        suffix = match[3] || 's'
        return (match[1].to_f * suffix_to_time[suffix].to_i).to_i
      end

      # ==== Returns
      #Single hash, with keys corresponding to Headers and values
      #corresponding to respective entries in Array.
      def array_to_hash(array, headers)
        Hash[*headers.zip(array).flatten] 
      end

      #The base file at the root of the URL path.
      # ==== Params
      #[url] string url 
      # ==== Returns
      #File name
      def url_basename(url)
        File.basename(URI.parse(url).path)
      end

      #Converts standard linefeed combos - CRLF, CR, LF - to whatever
      #the system newline is, aka "\n".
      # ==== Returns
      #String with normalized newlines
      def normalize_newlines(text)
        text.gsub!("\r\n", "\n")
        text.gsub!("\r", "\n")
        text.gsub!("\f", "\n")
        text
      end

      #Does a natural-feeling conversion between plain text linebreaks
      #and HTML P and BR tags, as typical with most web comment forms.
      # ==== Returns
      #Text with double newlines converted to P tags, single
      #newlines converted to BR tags, and the original newlines
      #restored.
      def newlines_to_html(text)
        text.gsub!(/\n\n+/, '<p>')
        text.gsub!(/\n/, '<br>')
        text.gsub!(/<p>/, "\n\n<p>")
        text.gsub!(/<br>/, "\n<br>")
        text
      end

      #Takes an array, returns a string with the array elements joined
      #with a comma, except for the last and second to last items,
      #which are joined with ' and '. For example: ['foo','bar'] => "foo
      #and bar"; ['foo','bar','baz'] => "foo, bar and baz"
      #
      #Also takes an optional flag which specifies whether to use an
      #oxford comma. Default is false. If set to true, the last and
      #second to last items will be joined with ', and'
      def join_in_english(array, oxford_comma=false)
        array = array.dup
        oxford_comma = (oxford_comma && array.count > 2) ? ',' : ''
        last = array.pop
        array.empty? ? last : [array.join(', '), last].join("#{oxford_comma} and ")
      end

      #Takes a block and calls that block with a path to a temporary
      #directory. Recursively deletes that directory when the block is
      #finished.
      def in_temp_dir
        dir = Dir.mktmpdir
        begin
          yield(dir)
        ensure
          FileUtils.remove_entry_secure(dir)
        end # begin
      end

      #Returns Typingpool's lib/typingpool/ root, usually for purposes
      #of locating templates or test fixtures.
      def lib_dir
        File.dirname(__FILE__)
      end

      #Returns Typingpool's root dir, that is, the root dir of the gem
      #from which this library is being loaded.
      def app_dir
        File.dirname(File.dirname(lib_dir))
      end

      #Returns true if this Ruby was built on Mac OS X
      def os_x?
        RUBY_PLATFORM.match(/\bdarwin/i)
      end

      #Returns true if anything appears to be waiting on STDIN
      def stdin_has_content?
        STDIN.fcntl(Fcntl::F_GETFL, 0) == 0
      end

      #Makes one or more HEAD requests to determine whether a
      #particular web resource is available.
      # ==== Params
      #[url]           URL as a string.
      #[max_redirects] Default 6. Maximum number of HTTP redirects to
      #                follow.
      # ==== Returns
      #True if the HTTP response code indicates success (after
      #following redirects). False if the HTTP response code indicates
      #an error (e.g. 4XX and 5XX response codes).
      def working_url?(url, max_redirects=6)
        response = request_url_with(url, max_redirects) do |url, http|
          http.request_head(url.path)
        end #request_url_with... do |url|
        response.kind_of?(Net::HTTPSuccess)
      end

      #Makes one or more web requests to fetch a resource. Follows
      #redirects by default.
      # ==== Params
      #[url]           URL as a string.
      #[max_redirects] Default 6. Maximum number of HTTP redirects to
      #                follow.
      # ==== Exceptions
      #Raises Error::HTTP if it receives an HTTP response code
      #indicating an error (after followinf redirects). Exception
      #message will include the response code and response message.
      # ==== Returns
      #A Net::HTTPResponse instance, if the request was successful.
      def fetch_url(url, max_redirects=6)
        response = request_url_with(url, max_redirects) do |url, http|
          http.request_get(url.path)
        end
        if response.kind_of?(Net::HTTPSuccess)
          return response
        else
          raise Error::HTTP, "HTTP error fetching '#{url.to_s}': '#{response.code}: #{response.message}'"
        end #if response.kind_of?
      end


      #protected 

      def request_url_with(url, max_redirects=6)
        seen = Set.new
        loop do
          url = URI.parse(url)
          if seen.include? url.to_s
            raise Error::HTTP, "Redirect infinite loop (at '#{url.to_s}')" 
          end
          if seen.count > max_redirects
            raise Error::HTTP, "Too many redirects (>#{max_redirects})" 
          end
          seen.add(url.to_s)
          #Die in a fire, net/http.
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = true if url.scheme == 'https'
          response = yield(url, http)
          if response.kind_of?(Net::HTTPRedirection)
            url = response['location']
          else
            return response
          end #if response.kind_of?...
        end #loop do
      end


    end #class << self
    require 'typingpool/utility/castable'
  end #Utility
end #Typingpool
