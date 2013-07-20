module Typingpool
  require 'minitest'
  class Test < Minitest::Test 
    require 'nokogiri'
    require 'fileutils'

    class << self
      attr_accessor :live
      attr_accessor :record

      def app_dir
        File.dirname(File.dirname(File.dirname(__FILE__)))
      end

    end #class << self

    self.record = ARGV.delete('--record')
    self.live = ARGV.delete('--live') || self.record

    def fixtures_dir
      File.join(Utility.lib_dir, 'test', 'fixtures')
    end

    def audio_dir
      File.join(fixtures_dir, 'audio')
    end

    def vcr_dir
      File.join(fixtures_dir, 'vcr')
    end

    def vcr_fixture_path_if_needed(filename)
      return nil if (Typingpool::Test.live && not(Typingpool::Test.rerecord))
      path = File.join(vcr_dir, filename)
      File.delete(path) if Typingpool::Test.rerecord
      path
    end

    def config
      if File.exists?(File.expand_path(Config.default_file))
        Config.file
      else
        Config.from_bundled_template
      end
    end

    def amazon_credentials?(config=self.config)
      config.amazon && config.amazon.key && config.amazon.secret
    end

    def skip_with_message(reason, skipping_what='')
      skipping_what = " #{skipping_what}" if not(skipping_what.empty?)
      skip ("Skipping#{skipping_what}: #{reason}")
      true
    end

    def skip_if_no_amazon_credentials(skipping_what='', config=self.config)
      if not (amazon_credentials?(config))
        skip_with_message('Missing or incomplete Amazon credentials', skipping_what)
      end
    end

    def s3_credentials?(config)
      amazon_credentials?(config) && config.amazon.bucket
    end

    def skip_if_no_s3_credentials(skipping_what='', config=self.config)
      if not (skip_if_no_amazon_credentials(skipping_what, config))
        if not(s3_credentials?(config))
          skip_with_message('No Amazon S3 credentials', skipping_what)
        end #if not(s3_credentials?...)
      end #if not(skip_if_no_amazon_credentials...)
    end

    def sftp_credentials?(config)
      config.sftp && config.sftp.user && config.sftp.host && config.sftp.url
    end

    def skip_if_no_sftp_credentials(skipping_what='', config=self.config)
      if not(sftp_credentials?(config))
        skip_with_message('No SFTP credentials', skipping_what)
      end #if not(sftp_credentials?...
    end

    def skip_if_no_upload_credentials(skipping_what='', config=self.config)
      if not(s3_credentials?(config) || sftp_credentials?(config))
        skip_with_message("No S3 or SFTP credentials in config", skipping_what)
      end #if not(s3_credentials?...
    end

    def add_goodbye_message(msg)
      at_exit do
        STDERR.puts msg
      end
    end

    def dummy_config(number=1)
      Typingpool::Config.file(File.join(fixtures_dir, "config-#{number}"))
    end


    def project_default
      Hash[
           :config_filename => '.config',
           :subtitle => "Typingpool's test interview transcription",
           :title => "Typingpool's Test & Interview",
           :chunks => '0:20',
           :unusual => ['Hack Day', 'Sunnyvale', 'Chad D'],
           :voice => ['Ryan', 'Havi, hacker'],
          ]
    end


    def in_temp_dir
      Typingpool::Utility.in_temp_dir{|dir| yield(dir) }
    end

    def working_url?(*args)
      Typingpool::Utility.working_url?(*args)
    end

    def working_url_eventually?(url, max_seconds=10, min_tries=2, max_redirects=6, seeking=true)
      start = Time.now.to_i
      tries = 0
      wait = 0
      loop do
        sleep wait
        return seeking if (working_url?(url, max_redirects) == seeking)
        wait = wait > 0 ? wait * 2 : 1
        tries += 1
      end until (tries >= min_tries) && ((Time.now.to_i + wait - start) >= max_seconds)
      not seeking
    end

    def broken_url_eventually?(url, max_seconds=10, min_tries=2, max_redirects=6)
      not(working_url_eventually?(url, max_seconds, min_tries, max_redirects, false))
    end

    def fetch_url(*args)
      Typingpool::Utility.fetch_url(*args)
    end

    require 'typingpool/test/script'
  end #Test
end #Typingpool
