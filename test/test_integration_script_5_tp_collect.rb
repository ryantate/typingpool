#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTpCollect < Typingpool::Test::Script

  def test_tp_collect
    with_temp_readymade_project do |dir|
      skip_if_no_upload_credentials('tp-collect integration test')
      skip_if_no_amazon_credentials('tp-collect integration test')
      copy_fixtures_to_transcripts_dir(dir, 'tp_collect_')
      begin
        project = transcripts_dir_project(dir)
        tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-1'))
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project, 'sandbox-assignment.csv')
        tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-2'))
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(4, transcript)
        assert_assignment_csv_has_transcription_count(4, project, 'sandbox-assignment.csv')
        tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-3'))
#       transcript = assert_has_transcript(dir) || assert_has_partial_transcript(dir)
#        assert_html_has_audio_count(7, transcript)
#        assert_assignment_csv_has_transcription_count(7, project, 'sandbox-assignment.csv')
      ensure
        rm_fixtures_from_transcripts_dir(dir, 'tp_collect_')
      end #begin
    end #with_temp_readymade_project do...
  end

end #TestTpCollect
