module Typingpool
  module App
    require 'vcr'
    require 'uri'
    class << self

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
        opts = {:record => (read_only ? :none : :new_episodes)}
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

    end #class << self
  end #App
end #Typingpool
