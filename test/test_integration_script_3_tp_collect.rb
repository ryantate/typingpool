#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpCollect < Typingpool::Test::Script
  require 'nokogiri'
  require 'fileutils'

  def test_tp_collect
    in_temp_tp_dir do |dir|
      tp_make(dir)
      copy_tp_collect_fixtures_to_temp_tp_dir(dir)
      begin
        project = temp_tp_dir_project(dir)
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-1'))
        end
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project)
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-2'))
        end
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(4, transcript)
        assert_assignment_csv_has_transcription_count(4, project)
        assert_nothing_raised do
          tp_collect_with_fixture(dir, File.join(vcr_dir, 'tp-collect-3'))
        end
        transcript = assert_has_transcript(dir)
        assert_html_has_audio_count(7, transcript)
        assert_assignment_csv_has_transcription_count(7, project)
      ensure
        rm_tp_collect_fixtures_from_temp_tp_dir(dir)
        tp_finish(dir)
      end #begin
    end #in_temp_tp_dir
  end

  def assert_has_transcript(dir, transcript_file='transcript.html')
    transcript_path = File.join(temp_tp_dir_project_dir(dir), transcript_file)
    assert(File.exists?(transcript_path))
    assert(not((transcript = IO.read(transcript_path)).empty?))
    transcript
  end

  def assert_has_partial_transcript(dir)
    assert_has_transcript(dir, 'transcript_in_progress.html')
  end

  def assert_assignment_csv_has_transcription_count(count, project)
    assert_equal(count, project.local.csv('data', 'assignment.csv').reject{|assignment| assignment['transcription'].to_s.empty?}.size)
  end

  def assert_html_has_audio_count(count, html)
    assert_equal(count, noko(html).css('audio').size)
  end

  def vcr_dir
    File.join(fixtures_dir, 'vcr')
  end

  def noko(html)
    Nokogiri::HTML(html) 
  end

  def copy_tp_collect_fixtures_to_temp_tp_dir(dir)
    with_tp_collect_fixtures_in_temp_tp_dir(dir) do |fixture_path, project_path|
      FileUtils.mv(project_path, File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}"))
      FileUtils.cp(fixture_path, project_path)
    end
  end

  def rm_tp_collect_fixtures_from_temp_tp_dir(dir)
    with_tp_collect_fixtures_in_temp_tp_dir(dir) do |fixture_path, project_path|
      path_to_orig = File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}")
      File.exists?(path_to_orig) or raise Test::Error, "Couldn't find original file '#{path_to_orig}' when trying to restore it to original location"
      FileUtils.rm(project_path)
      FileUtils.mv(path_to_orig, project_path)
    end
  end
end #TestTpCollect
