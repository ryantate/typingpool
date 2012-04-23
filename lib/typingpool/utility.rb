module Typingpool
  class Utility
    require 'open3'
    require 'uri'
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
    end #class << self
  end #Utility
end #Typingpool
