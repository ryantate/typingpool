module Typingpool
  require 'minitest'
  require 'typingpool/utility/test'
  
  class Test < Minitest::Test 
    include Utility::Test
    
    class << self
      attr_accessor :live
      attr_accessor :record
    end #class << self

    self.record = ARGV.delete('--record')
    self.live = ARGV.delete('--live')

    def skip_with_message(reason, skipping_what='')
      skipping_what = " #{skipping_what}" unless skipping_what.empty?
      skip ("Skipping#{skipping_what}: #{reason}")
      true
    end

    def skip_if_no_amazon_credentials(skipping_what='', config=self.config)
      if not (amazon_credentials?(config))
        skip_with_message('Missing or incomplete Amazon credentials', skipping_what)
      end
    end

    def skip_if_no_s3_credentials(skipping_what='', config=self.config)
      if not (skip_if_no_amazon_credentials(skipping_what, config))
        if not(s3_credentials?(config))
          skip_with_message('No Amazon S3 credentials', skipping_what)
        end #if not(s3_credentials?...)
      end #if not(skip_if_no_amazon_credentials...)
    end

    def skip_if_no_sftp_credentials(skipping_what='', config=self.config)
      if not(sftp_credentials?(config))
        skip_with_message('No SFTP credentials', skipping_what)
      end #if not(sftp_credentials?...
    end

    def skip_during_vcr_playback(skipping_what='')
      skip_with_message("Runs only with --live or --record option", skipping_what) unless (Typingpool::Test.live || Typingpool::Test.record)
    end

    def skip_if_no_upload_credentials(skipping_what='', config=self.config)
      if not(s3_credentials?(config) || sftp_credentials?(config))
        skip_with_message("No S3 or SFTP credentials in config", skipping_what)
      end #if not(s3_credentials?...
    end

    require 'typingpool/test/script'
  end #Test
end #Typingpool
