#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpReview < Typingpool::Test::Script

  def test_tp_review
    in_temp_tp_dir do |dir|
      skip_if_no_upload_credentials('tp-review integration test')
      skip_if_no_amazon_credentials('tp-review integration test')
      tp_make(dir)
      copy_fixtures_to_temp_tp_dir(dir, 'tp_review_')
      project = temp_tp_dir_project(dir)
        assert_equal(7, project.local.csv('data','assignment.csv').reject{|assignment| assignment['hit_id'].to_s.empty? }.count)
      begin
        output = nil
        assert_nothing_raised do
          output = tp_review_with_fixture(dir, File.join(fixtures_dir, 'vcr', 'tp-review-1'), %w(a r a r s q))
        end
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        assert_equal(5, project.local.csv('data','assignment.csv').reject{|assignment| assignment['hit_id'].to_s.empty? }.count)
        reviews = split_reviews(output[:out])
        assert_match(reviews[1], /Interview\.00\.00/)
        #we can't specify leading \b boundaries because the ansi
        #escape sequences mess that up
        assert_match(reviews[1], /Approved\b/i)
        assert_match(reviews[2], /Interview\.00\.20/)
        assert_match(reviews[2], /reason\b/i)
        assert_match(reviews[2], /Rejected\b/i)
        assert_match(reviews[3], /Interview\.00\.40/)
        assert_match(reviews[3], /Approved\b/i)
        assert_match(reviews[4], /Interview\.01\.20/)
        assert_match(reviews[4], /reason\b/i)
        assert_match(reviews[4], /Rejected\b/i)
        assert_match(reviews[5], /Interview\.01\.40/)
        assert_match(reviews[5], /Skipping\b/i)
        assert_match(reviews[6], /Interview\.02\.00/)
        assert_match(reviews[6], /Quitting\b/i)
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project)

        assert_nothing_raised do
          output = tp_review_with_fixture(dir, File.join(fixtures_dir, 'vcr', 'tp-review-2'), %w(a r))
        end
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        assert_equal(4, project.local.csv('data','assignment.csv').reject{|assignment| assignment['hit_id'].to_s.empty? }.count)
        reviews = split_reviews(output[:out])
        assert_match(reviews[1], /Interview\.01\.40/)
        assert_match(reviews[1], /Approved\b/i)
        assert_match(reviews[2], /Interview\.02\.00/)
        assert_match(reviews[2], /reason\b/i)
        assert_match(reviews[2], /Rejected\b/i)
        transcript = assert_has_partial_transcript(dir)
        assert_html_has_audio_count(3, transcript)
        assert_assignment_csv_has_transcription_count(3, project)
      ensure
        rm_fixtures_from_temp_tp_dir(dir, 'tp_review_')
        tp_finish(dir)
      end #begin
    end #in_temp_tp_dir
  end

  def split_reviews(output)
    output.split(/Transcript for\b/)
  end

end #class TestTpReview
