module Typingpool
  module Utility
    module Test
      def fixtures_dir
        File.join(Utility.lib_dir, 'test', 'fixtures')
      end

      def audio_dir
        File.join(fixtures_dir, 'audio')
      end

      def vcr_dir
        File.join(fixtures_dir, 'vcr')
      end

      def delete_vcr_fixture(fixture_name)
        fixture_path = File.join(vcr_dir, [fixture_name, '.yml'].join)
        File.delete(fixture_path) if File.exist? fixture_path
      end
      
      def cleared_vcr_fixture_path_for(fixture_name)
        if Typingpool::Test.record
          delete_vcr_fixture(fixture_name)
        end
        if (Typingpool::Test.record || not(Typingpool::Test.live))
          File.join(vcr_dir, fixture_name)
        end
      end

      def with_vcr(fixture_name, config, opts={})
        if fixture = cleared_vcr_fixture_path_for(fixture_name)
          read_only = not(Typingpool::Test.record)
          Typingpool::App.vcr_load(fixture, config, read_only, opts)
        end
        begin
          yield
        ensure
          Typingpool::App.vcr_stop
        end
      end

      def config
        if File.exist?(File.expand_path(Config.default_file))
          Config.file
        else
          Config.from_bundled_template
        end
      end

      def amazon_credentials?(config=self.config)
        config.amazon && config.amazon.key && config.amazon.secret
      end

      def s3_credentials?(config)
        amazon_credentials?(config) && config.amazon.bucket
      end

      def sftp_credentials?(config)
        config.sftp && config.sftp.user && config.sftp.host && config.sftp.url
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
             :chunks => '0:22',
             :unusual => ['Hack Day', 'Sunnyvale', 'Chad D'],
             :voice => ['Ryan', 'Havi, hacker'],
            ]
      end

      def works_eventually?(max_seconds=10, min_tries=2)
        start = Time.now.to_i
        tries = 0
        wait = 0
        until ((tries >= min_tries) && ((Time.now.to_i + wait - start) >= max_seconds)) do
          sleep wait
          return true if yield
          wait = wait > 0 ? wait * 2 : 1
          tries += 1
        end
        false
      end

      def working_url_eventually?(url, max_seconds=10, min_tries=2, max_redirects=6)
        works_eventually?(max_seconds, min_tries) do
          Utility.working_url?(url, max_redirects)
        end
      end

      def broken_url_eventually?(url, max_seconds=10, min_tries=2, max_redirects=6)
        works_eventually?(max_seconds, min_tries) do
          not(Utility.working_url?(url, max_redirects))
        end
      end

      
    end #Test
  end #Utility
end #Typingpool
