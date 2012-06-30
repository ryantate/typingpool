module Typingpool
  class Error < StandardError 
    class Test < Error; end
    class Shell < Error; end
    class Argument < Error
      class Format < Argument; end
    end
    class File < Error
      class NotExists < File; end
      class Remote < File
        class SFTP < Remote; end
        class S3 < Remote
          class Credentials < S3; end
        end #S3
      end #Remote
    end #File
    class Amazon < Error
      class UnreviewedContent < Amazon; end
    end #Amazon
    class HTTP < Error; end
  end #Error
end #Typingpool
