#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'typingpool/utility/test'
include Typingpool::Utility::Test

class TestTpFinish < Typingpool::Test::Script
  def test_tp_finish_on_audio_files_with_sftp
    test_name = 'tp-finish sftp audio test'
    skip_if_no_sftp_credentials(test_name)
    skip_if_no_amazon_credentials(test_name)
    skip_during_vcr_playback(test_name)
    with_temp_readymade_project do |dir|
      simulate_failed_audio_upload_in(dir)
      begin
        #get audio uploaded by calling tp-make on existing project
        tp_make(dir)
        project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(dir)))
        csv = project.local.file('data', 'assignment.csv').as(:csv)
        urls = csv.map{|assignment| assignment['audio_url'] }
        refute_empty(urls)
        assert_all_assets_have_upload_status(csv, 'audio', 'yes')
        assert_equal(urls.count, urls.select{|url| working_url_eventually? url}.count)
      ensure
        tp_finish_outside_sandbox(dir)
      end #begin
      assert_equal(urls.count, urls.select{|url| broken_url_eventually? url }.count)
      assert_all_assets_have_upload_status(csv, 'audio', 'no')
    end #with_temp_readymade_project do |dir|
  end

  def test_tp_finish_on_audio_files_with_s3
    skip_if_no_s3_credentials('tp-finish s3 audio test')
    skip_if_no_amazon_credentials('tp-finish s3 audio test')
    with_temp_readymade_project do |dir|
      config = reconfigure_for_s3(Typingpool::Config.file(config_path(dir)))
      s3_config_path = write_config(dir, config)
      project = Typingpool::Project.new(project_default[:title], config)
      reconfigure_project(project)
      simulate_failed_audio_upload_in(dir, s3_config_path)
      begin
        #get audio uploaded by calling tp-make on existing project
        tp_make_with_vcr(dir, 'tp_finish_1', s3_config_path)
        csv = project.local.file('data', 'assignment.csv').as(:csv)
        urls = csv.map{|assignment| assignment['audio_url'] }
        refute_empty(urls)
        assert_all_assets_have_upload_status(csv, 'audio', 'yes')
        assert_equal(urls.count, urls.select{|url| working_url_eventually? url}.count) if (Typingpool::Test.live || Typingpool::Test.record)
      ensure
        tp_finish_outside_sandbox_with_vcr(dir, 'tp_finish_2', s3_config_path)
      end #begin
      assert_equal(urls.count, urls.select{|url| broken_url_eventually? url }.count) if (Typingpool::Test.live || Typingpool::Test.record)
      assert_all_assets_have_upload_status(csv, 'audio', 'no')
    end #with_temp_readymade_project do |dir|
  end


  def test_tp_finish_on_amazon_hits
    skip_if_no_amazon_credentials('tp-finish Amazon test')
    skip_if_no_s3_credentials('tp-finish Amazon test')
    with_temp_readymade_project do |dir|
      config = reconfigure_for_s3(Typingpool::Config.file(config_path(dir)))
      s3_config_path = write_config(dir, config)
      project = Typingpool::Project.new(project_default[:title], config)
      reconfigure_project(project)
      copy_tp_assign_fixtures(dir, 'tp_finish_3', s3_config_path)
      sandbox_csv=nil
      csv=nil
      with_vcr('tp_finish_4', config, {
                 :preserve_exact_body_bytes => true,
                 :match_requests_on => [:method, vcr_core_host_matcher]
               }) do
        begin
          tp_assign_with_vcr(dir, 'tp_finish_3', s3_config_path)
          csv = project.local.file('data', 'assignment.csv').as(:csv)
          sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
          assert_all_assets_have_upload_status(sandbox_csv, 'assignment', 'yes')
          assert_all_assets_have_upload_status(csv, 'audio', 'yes')
          Typingpool::Amazon.setup(:sandbox => true, :config => Typingpool::Config.file(config_path(dir)))
          results = Typingpool::Amazon::HIT.all_for_project(project.local.id)
          refute_empty(results)
        ensure
          tp_finish_with_vcr(dir, 'tp_finish_5', s3_config_path)
        end #begin
        assert_empty(Typingpool::Amazon::HIT.all_for_project(project.local.id))
        results.each do |result|
          #The original HIT might be gone, or there and marked
          #'disposed', depending whether Amazon has swept the server for
          #dead HITs yet
          begin 
            hit = RTurk::Hit.find(result.id)
            assert_match(/^dispos/i, hit.status)
          rescue RTurk::InvalidRequest => exception
            assert_match(/HITDoesNotExist/i, exception.message)
          end #begin
        end #results.each...
      end #with_vcr do...
      refute(File.exist? sandbox_csv)
      assert_all_assets_have_upload_status(csv, 'audio', 'no')
    end #with_temp_readymade_project do...
  end

  def test_tp_finish_with_missing_files
    skip_if_no_amazon_credentials('tp-finish missing files test')
    skip_if_no_s3_credentials('tp-finish missing files test')
    with_temp_readymade_project do |dir|
      config = reconfigure_for_s3(Typingpool::Config.file(config_path(dir)))
      s3_config_path = write_config(dir, config)
      project = Typingpool::Project.new(project_default[:title], config)
      reconfigure_project(project)
      simulate_failed_audio_upload_in(dir, s3_config_path)
      begin
        tp_make_with_vcr(dir, 'tp_finish_6', s3_config_path)
        csv = project.local.file('data', 'assignment.csv').as(:csv)
        assignments = csv.read
        urls = assignments.map{|assignment| assignment['audio_url'] }
        assert_equal(urls.count, urls.select{|url| working_url_eventually? url }.count) if (Typingpool::Test.live || Typingpool::Test.record)
        assert_all_assets_have_upload_status(csv, 'audio', 'yes')
        bogus_url = urls.first.sub(/\.mp3/, '.foo.mp3')
        refute_equal(urls.first, bogus_url)
        refute(Typingpool::Utility.working_url? bogus_url) if (Typingpool::Test.live || Typingpool::Test.record)
        bogus_assignment = assignments.first.dup
        bogus_assignment['audio_url'] = bogus_url
        assignments.insert(1, bogus_assignment)
        csv.write(assignments)
        assignments = csv.read
        refute(Typingpool::Utility.working_url? assignments[1]['audio_url']) if (Typingpool::Test.live || Typingpool::Test.record)
      ensure
        tp_finish_outside_sandbox_with_vcr(dir, 'tp_finish_7', s3_config_path)
      end #begin
      assert_all_assets_have_upload_status(csv, 'audio', 'no')
      urls = csv.map{|assignment| assignment['audio_url'] }
      assert_equal(urls.count, urls.select{|url| broken_url_eventually? url }.count) if (Typingpool::Test.live || Typingpool::Test.record)
    end #with_temp_readymade_project do...
  end


  def test_tp_finish_warns_on_data_loss
    skip_if_no_amazon_credentials('tp-finish warns on data loss test')
    skip_if_no_s3_credentials('tp-finish wanrs on data loss test')
    with_temp_readymade_project do |transcripts_dir|
      copy_fixtures_to_project_dir('tp_finish_4_', File.join(transcripts_dir, project_default[:title]))
      project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(transcripts_dir)))
      begin
        assert(File.exist? File.join(project.local, 'data','sandbox-assignment.csv'))
        assert_equal(6, project.local.file('data','sandbox-assignment.csv').as(:csv).reject{|assignment| assignment['hit_id'].to_s.empty? }.count)
        output = tp_review_with_fixture(transcripts_dir, 'tp_finish_9', %w(a r q), false, project_default[:title])
        assert_equal(0, output[:status].to_i)
        assert_equal(1, project_transcript_count(project, 'sandbox-assignment.csv'))
        assert_equal(1, project_hits_rejected(project, 'sandbox-assignment.csv').count)
        assert_equal(1, project_hits_approved(project, 'sandbox-assignment.csv').count)
        assert_equal(1, project_transcript_count(project, 'sandbox-assignment.csv'))
        out, err = tp_finish_inside_sandbox_with_vcr(transcripts_dir, 'tp_finish_10', config_path(transcripts_dir), false, false, %w(s a))
        assert_match(/not been added/, err)
        assert_match(/unreviewed submission/, err)
        assert_equal(2, project_transcript_count(project, 'old-sandbox-assignment.csv'))
        assert_equal(2, project_hits_approved(project, 'old-sandbox-assignment.csv').count)
      ensure
        restore_project_dir_from_fixtures('tp_finish_4_', File.join(transcripts_dir, project_default[:title]))
      end #begin
      
    end #with_temp_readymade_project do...
  end
  
  def test_abort_on_config_mismatch
    skip_if_no_s3_credentials('tp-finish abort on config mismatch test')
    with_temp_readymade_project do |dir|
      config = reconfigure_for_s3(Typingpool::Config.file(config_path(dir)))
      good_config_path = write_config(dir, config, '.config_s3_good')
      reconfigure_project(Typingpool::Project.new(project_default[:title], config))
      simulate_failed_audio_upload_in(dir, good_config_path)
      assert(config.amazon.bucket)
      new_bucket = 'configmismatch-test'
      refute_equal(new_bucket, config.amazon.bucket)
      config.amazon.bucket = new_bucket
      bad_config_path = write_config(dir, config, '.config_s3_bad')
      exception = assert_raises(Typingpool::Error::Shell) do
        tp_finish_outside_sandbox_with_vcr(dir, 'tp_finish_8', bad_config_path)
      end #assert_raises...
      assert_match(/\burls don't look right\b/i, exception.message)
    end #with_temp_readymade_project do...
  end


  def project_hits_rejected(project, csv='sandbox-assignment.csv')
    project.local.file('data', csv).as(:csv).select{|assignment| assignment_rejected?(assignment) }
  end
  
  def project_hits_approved(project, csv='sandbox-assignment.csv')
    project.local.file('data', csv).as(:csv).select{|assignment| assignment_approved?(assignment) }
  end

  def project_hits_pending(project, csv='sandbox-assignment.csv')
    project.local.file('data', csv).as(:csv).reject{|assignment| assignment_approved?(assignment) || assignment_rejected?(assignment)}
  end

  def assignment_rejected?(assignment)
    assignment['hit_id'].to_s.empty?
  end

  def assignment_approved?(assignment)
    assignment['transcript'].to_s.match(/\S/)
  end

  
end #TestTpFinish
