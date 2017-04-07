#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTpReview < Typingpool::Test::Script

  def test_tp_review_with_project_specified
    with_temp_readymade_project do |dir|
      skip_if_no_upload_credentials('tp-review integration test')
      skip_if_no_amazon_credentials('tp-review integration test')
      copy_fixtures_to_project_dir('tp_review_', File.join(dir, project_default[:title]))
      project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(dir)))
      assert(File.exist? File.join(project.local, 'data','sandbox-assignment.csv'))
      assert_equal(6, project.local.file('data','sandbox-assignment.csv').as(:csv).reject{|assignment| assignment['hit_id'].to_s.empty? }.count)
      begin
        output = nil
        output = tp_review_with_fixture(dir, 'tp-review-1', %w(a r a r s q), false, project_default[:title])
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        assert_equal(2, project_hits_approved(project).count)
        assert_equal(2, project_hits_rejected(project).count)
        assert_equal(2, project_hits_pending(project).count)
        reviews = split_reviews(output[:out])
        assert_match(/Interview\.00\.00/, reviews[1])
        #we can't specify leading \b boundaries because the ansi
        #escape sequences mess that up
        assert_match(/Approved\b/i, reviews[1])
        assert_match(/Interview\.00\.22/, reviews[2])
        assert_match(/reason\b/i, reviews[2])
        assert_match(/Rejected\b/i, reviews[2])
        assert_match(/Interview\.00\.44/, reviews[3])
        assert_match(/Approved\b/i, reviews[3])
        assert_match(/Interview\.01\.06/, reviews[4])
        assert_match(/reason\b/i, reviews[4])
        assert_match(/Rejected\b/i, reviews[4])
        assert_match(/Interview\.01\.28/, reviews[5])
        assert_match(/Skipping\b/i, reviews[5])
        assert_match(/Interview\.01\.50/, reviews[6])
        assert_match(/Quitting\b/i, reviews[6])
        transcript = assert_has_partial_transcript(project)
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project, 'sandbox-assignment.csv')

        output = tp_review_with_fixture(dir, 'tp-review-2', %w(a q), false, project_default[:title])
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        assert_equal(3, project_hits_approved(project).count)
        assert_equal(2, project_hits_rejected(project).count)
        assert_equal(1, project_hits_pending(project).count)
        reviews = split_reviews(output[:out])
        assert_match(/Interview\.01\.28/, reviews[1])
        assert_match(/Approved\b/i, reviews[1])
        assert_match(/Interview\.01\.50/, reviews[2])
        assert_match(/Quitting\b/i, reviews[2])
        transcript = assert_has_partial_transcript(project)
        assert_html_has_audio_count(3, transcript)
        assert_assignment_csv_has_transcription_count(3, project, 'sandbox-assignment.csv')

        output = tp_review_with_fixture(dir, 'tp-review-6', %w(q), false, project_default[:title])
        assert_equal(4, project_hits_approved(project).count)
        assert_equal(2, project_hits_rejected(project).count)
        assert_equal(0, project_hits_pending(project).count)
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        transcript = assert_has_partial_transcript(project)
        assert_html_has_audio_count(4, transcript)
        assert_assignment_csv_has_transcription_count(4, project, 'sandbox-assignment.csv')
      ensure
        restore_project_dir_from_fixtures('tp_review_', File.join(dir, project_default[:title]))
      end #begin
    end #with_temp_readymade_project do...
  end

   def test_tp_review_without_project_specified
     skip_if_no_upload_credentials('tp-review integration test')
     skip_if_no_amazon_credentials('tp-review integration test')
     with_temp_readymade_project do |transcripts_dir|
       project_title = [ project_default[:title], "Second #{project_default[:title]}" ] 
       FileUtils.cp_r(File.join(transcripts_dir, project_title[0]), File.join(transcripts_dir, project_title[1]))
       copy_fixtures_to_project_dir('tp_review2a_', File.join(transcripts_dir, project_title[0]))
       copy_fixtures_to_project_dir('tp_review2b_', File.join(transcripts_dir, project_title[1]))
       project = project_title.sort.map{|title| Typingpool::Project.new(title, Typingpool::Config.file(config_path(transcripts_dir))) }      
       project.each do |project|
         assert(File.exist? File.join(project.local, 'data','sandbox-assignment.csv'))
         assert_equal(6, project_hits_pending(project).count)
       end
      begin
        output = tp_review_with_fixture(transcripts_dir, 'tp-review-3', %w(a r a r s s r a a s a q), false)
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        reviews = split_reviews(output[:out])
        
        assert_equal(2, project_hits_approved(project[0]).count)
        assert_equal(2, project_hits_rejected(project[0]).count)
        assert_equal(2, project_hits_pending(project[0]).count)
        assert_match(/Interview\.00\.00/, reviews[1])
        #we can't specify leading \b boundaries because the ansi
        #escape sequences mess that up
        assert_match(/Approved\b/i, reviews[1])
        assert_match(/Interview\.00\.22/, reviews[2])
        assert_match(/reason\b/i, reviews[2])
        assert_match(/Rejected\b/i, reviews[2])
        assert_match(/Interview\.00\.44/, reviews[3])
        assert_match(/Approved\b/i, reviews[3])
        assert_match(/Interview\.01\.06/, reviews[4])
        assert_match(/reason\b/i, reviews[4])
        assert_match(/Rejected\b/i, reviews[4])
        assert_match(/Interview\.01\.28/, reviews[5])
        assert_match(/Skipping\b/i, reviews[5])
        assert_match(/Interview\.01\.50/, reviews[6])
        assert_match(/Skipping/i, reviews[6])
        transcript = assert_has_partial_transcript(project[0])
        assert_html_has_audio_count(2, transcript)
        assert_assignment_csv_has_transcription_count(2, project[0], 'sandbox-assignment.csv')
        
        assert_equal(3, project_hits_approved(project[1]).count)
        assert_equal(1, project_hits_rejected(project[1]).count)
        assert_equal(2, project_hits_pending(project[1]).count)
        assert_match(/Interview\.00\.00/, reviews[7])
        assert_match(/Rejected\b/i, reviews[7])
        assert_match(/reason\b/i, reviews[7])
        assert_match(/Interview\.00\.22/, reviews[8])
        assert_match(/Approved\b/i, reviews[8])
        assert_match(/Interview\.00\.44/, reviews[9])
        assert_match(/Approved\b/i, reviews[9])
        assert_match(/Interview\.01\.06/, reviews[10])
        assert_match(/Skipping\b/i, reviews[10])
        assert_match(/Interview\.01\.28/, reviews[11])
        assert_match(/Approved\b/i, reviews[11])
        assert_match(/Interview\.01\.50/, reviews[12])
        assert_match(/Quitting\b/i, reviews[12])
        transcript = assert_has_partial_transcript(project[1])
        assert_html_has_audio_count(3, transcript)
        assert_assignment_csv_has_transcription_count(3, project[1], 'sandbox-assignment.csv')

        output = tp_review_with_fixture(transcripts_dir, 'tp-review-4', %w(a r s a), false)
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        reviews = split_reviews(output[:out])
        
        assert_equal(3, project_hits_approved(project[0]).count)
        assert_equal(3, project_hits_rejected(project[0]).count)
        assert_equal(0, project_hits_pending(project[0]).count)
        assert_match(/Interview\.01\.28/, reviews[1])
        assert_match(/Approved\b/i, reviews[1])
        assert_match(/Interview\.01\.50/, reviews[2])
        assert_match(/reason\b/i, reviews[2])
        assert_match(/Rejected\b/i, reviews[2])
        transcript = assert_has_partial_transcript(project[0])
        assert_html_has_audio_count(3, transcript)
        assert_assignment_csv_has_transcription_count(3, project[0], 'sandbox-assignment.csv')

        assert_equal(4, project_hits_approved(project[1]).count)
        assert_equal(1, project_hits_rejected(project[1]).count)
        assert_equal(1, project_hits_pending(project[1]).count)
        assert_match(/Interview\.01\.06/, reviews[3])
        assert_match(/Skipping\b/i, reviews[3])
        assert_match(/Interview\.01\.50/, reviews[4])
        assert_match(/Approved\b/i, reviews[4])
        transcript = assert_has_partial_transcript(project[1])
        assert_html_has_audio_count(4, transcript)
        assert_assignment_csv_has_transcription_count(4, project[1], 'sandbox-assignment.csv')

        output = tp_review_with_fixture(transcripts_dir, 'tp-review-5', %w(q), false)
        assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
        assert_equal(5, project_hits_approved(project[1]).count)
        assert_equal(1, project_hits_rejected(project[1]).count)
        assert_equal(0, project_hits_pending(project[1]).count)
        transcript = assert_has_partial_transcript(project[1])
        assert_html_has_audio_count(5, transcript)
        assert_assignment_csv_has_transcription_count(5, project[1], 'sandbox-assignment.csv')
      ensure
        restore_project_dir_from_fixtures('tp_review2a_', File.join(transcripts_dir, project_title[0]))
        restore_project_dir_from_fixtures('tp_review2b_', File.join(transcripts_dir, project_title[1]))
      end #begin      
    end #with_temp_readymade_project
  end
  

   def project_hits_rejected(project)
     project.local.file('data','sandbox-assignment.csv').as(:csv).select{|assignment| assignment_rejected?(assignment) }
   end
   
   def project_hits_approved(project)
     project.local.file('data','sandbox-assignment.csv').as(:csv).select{|assignment| assignment_approved?(assignment) }
   end

   def project_hits_pending(project)
     project.local.file('data','sandbox-assignment.csv').as(:csv).reject{|assignment| assignment_approved?(assignment) || assignment_rejected?(assignment)}
   end

   def assignment_rejected?(assignment)
     assignment['hit_id'].to_s.empty?
   end

   def assignment_approved?(assignment)
     assignment['transcript'].to_s.match(/\S/)
   end
   
 end #class TestTpReview
