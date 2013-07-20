module Typingpool
  module App
    require 'vcr'
    class << self
      #Begins recording of an HTTP mock fixture (for automated
      #testing) using the great VCR gem. Automatically filters your
      #Config#amazon#key and Config#amazon#secret from the recorded
      #fixture, and automatically determines the "cassette" name and
      #"cassette library" dir from the supplied path.
      # ==== Params
      # [fixture_path] Path to where you want the HTTP fixture
      #                recorded, including filename.
      # [config]       A Config instance, used to extract the
      #                Config#amazon#secret and Config#amazon#key that
      #                will be filtered from the fixture.
      # ==== Returns
      # Result of calling VCR.insert_cassette.
      def vcr_record(fixture_path, config)
        VCR.configure do |c|
          c.cassette_library_dir = File.dirname(fixture_path)
          c.hook_into :webmock 
          c.filter_sensitive_data('<AWS_KEY>'){ config.amazon.key }
          c.filter_sensitive_data('<AWS_SECRET>'){ config.amazon.secret }
        end
        VCR.insert_cassette(File.basename(fixture_path, '.*'), :record => :new_episodes)
      end

      #Stops recording of the last call to vcr_record. Returns the
      #result of VCR.eject_cassette.
      def vcr_stop
        VCR.eject_cassette
      end
    end #class << self
  end #App
end #Typingpool
