module Typingpool
  class Test 
    class Script < Test 
      require 'typingpool'
      require 'open3'
      require 'fileutils'
      require 'nokogiri'
      require 'typingpool/utility/test/script'

      include Utility::Test::Script

      #Overrides method in Utility::Test::Script
      def do_later
        Minitest.after_run{ yield }
      end

      def setup_s3_config_with_bad_password(dir, config=Config.file(config_path(dir)))
        bad_password = 'f'
        refute_equal(config.to_hash['amazon']['secret'], bad_password)
        config.to_hash['amazon']['secret'] = bad_password
        setup_s3_config(dir, config, '.config_s3_bad')
      end


      def assert_has_transcript(dir, transcript_file='transcript.html')
        transcript_path = File.join(transcripts_dir_project(dir).local, transcript_file)
        assert(File.exist?(transcript_path))
        assert(not((transcript = IO.read(transcript_path)).empty?))
        transcript
      end

      def assert_has_partial_transcript(dir)
        assert_has_transcript(dir, 'transcript_in_progress.html')
      end

      def assert_assignment_csv_has_transcription_count(count, project, which_csv='assignment.csv')
        assert_equal(count, project_transcript_count(project, which_csv))
      end

      def assert_html_has_audio_count(count, html)
        assert_equal(count, Nokogiri::HTML(html).css('audio').size)
      end

      def assert_all_assets_have_upload_status(assignment_csv, type, status)
        recorded_uploads = assignment_csv.map{|assignment| assignment["#{type}_uploaded"] }
        refute_empty(recorded_uploads)
        assert_equal(recorded_uploads.count, recorded_uploads.select{|uploaded| uploaded == status }.count)
      end

      def assert_script_abort_match(args, regex)
        with_temp_transcripts_dir do |dir|
          exception = assert_raises(Typingpool::Error::Shell) do
            yield([*args, '--config', config_path(dir)])
          end
          assert_match(regex, exception.message)
        end #with_temp_transcripts_dir do...
      end

    end #Script
  end #Test
end #Typingpool
