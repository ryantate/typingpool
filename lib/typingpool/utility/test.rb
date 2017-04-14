module Typingpool
  module Utility
    module Test
      require 'vcr'
      require 'uri'
      
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
      
      def cleared_vcr_fixture_path_for(fixture_name, can_ever_run_live=true, are_recording=Typingpool::Test.record)
        if are_recording
          delete_vcr_fixture(fixture_name)
        end
        if (are_recording || not(Typingpool::Test.live) || not(can_ever_run_live))
          File.join(vcr_dir, fixture_name)
        end
      end

      def with_vcr(fixture_name, config, opts={})
        if fixture = cleared_vcr_fixture_path_for(fixture_name)
          read_only = not(Typingpool::Test.record)
          vcr_load(fixture, config, read_only, opts)
        end
        begin
          yield
        ensure
          vcr_stop
        end
      end

            #Loads an HTTP mock fixture for playback (default) or
      #recording. Used in automated tests. Uses the great VCR gem.
      #
      #Automatically filters your Config#amazon#key and
      #Config#amazon#secret from the recorded fixture, and
      #automatically determines the "cassette" name and "cassette
      #library" dir from the supplied path.
      # ==== Params
      # [fixture_path] Path to where you want the HTTP fixture
      #                recorded, including filename.
      # [config]       A Config instance, used to extract the
      #                Config#amazon#secret and Config#amazon#key that
      #                will be filtered from the fixture.
      # [read_only]    Default is true. Set to false to enable recording.
      # [vcr_params]   Default is nil. A hash of params to pass to
      #                VCR.insert_cassette (same set of params that
      #                can be passed to VCR.use_cassette), like
      #                :preserve_exact_body_bytes or
      #                :match_requests_on => [:url, :matcher]. If nil,
      #                no extra params will be passed.
      # ==== Returns
      # Result of calling VCR.insert_cassette.
      def vcr_load(fixture_path, config, read_only=true, vcr_params=nil)
        VCR.configure do |c|
          c.cassette_library_dir = File.dirname(fixture_path)
          c.hook_into :webmock 
          c.filter_sensitive_data('<AWS_KEY>'){ config.amazon.key }
          c.filter_sensitive_data('<AWS_SECRET>'){ config.amazon.secret }
          c.before_record do |interaction|
            if interaction.request.body.size > 10000
              interaction.request.body = '<BIG_UPLOAD>'
            end
          end #c.before_record do...
        end
        WebMock.allow_net_connect! 
        opts = {:record => (read_only ? :none : :once)}
        opts.merge!(vcr_params) if vcr_params
        VCR.turn_on!
        VCR.insert_cassette(File.basename(fixture_path, '.*'), 
                            opts
                           )

      end
      
      #Stops playing/recording from the last call to vcr_load. Returns the
      #result of VCR.eject_cassette.
      def vcr_stop
        VCR.eject_cassette
        VCR.turn_off!
      end

      #great for s3 because we don't have to worry about changing
      #bucket names, only matches as far as s3.amazonaws.com
      def vcr_core_host_matcher
        lambda do |request1, request2|
          core_host = lambda{|host| host.split(/\./).reverse.slice(0, 3).reverse.join('.')}
          core_host.call(URI(request1.uri).host) == core_host.call(URI(request2.uri).host)
        end #lambda do...
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
