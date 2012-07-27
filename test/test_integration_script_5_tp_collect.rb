#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpCollect < Typingpool::Test::Script
  require 'fileutils'

  def test_tp_collect
    in_temp_tp_dir do |dir|
      skip_if_no_upload_credentials('tp-collect integration test')
      skip_if_no_amazon_credentials('tp-collect integration test')
      tp_make(dir)
      copy_fixtures_to_temp_tp_dir(dir, 'tp_collect_')
      begin
        project = temp_tp_dir_project(dir)
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-1'))
        end
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project, 'sandbox-assignment.csv')
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-2'))
        end
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(4, transcript)
        assert_assignment_csv_has_transcription_count(4, project, 'sandbox-assignment.csv')
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-3'))
        end
        transcript = assert_has_transcript(dir)
        assert_html_has_audio_count(7, transcript)
        assert_assignment_csv_has_transcription_count(7, project, 'sandbox-assignment.csv')
      ensure
        rm_fixtures_from_temp_tp_dir(dir, 'tp_collect_')
        tp_finish(dir)
      end #begin
    end #in_temp_tp_dir
  end

end #TestTpCollect
