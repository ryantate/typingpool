#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTpFinish < Typingpool::Test::Script
  def tp_finish_on_audio_files_with(dir, config_path)
    skip_if_no_amazon_credentials('tp-finish audio test')
    skip_if_no_upload_credentials('tp-finish audio test')
    simulate_failed_audio_upload_in(config_path)
    tp_make(dir, config_path)
    project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path))
    csv = project.local.file('data', 'assignment.csv').as(:csv)
    urls = csv.map{|assignment| assignment['audio_url'] }
    refute_empty(urls)
    assert_all_assets_have_upload_status(csv, ['audio'], 'yes')
    assert_equal(urls.count, urls.select{|url| working_url_eventually? url}.count)
    tp_finish_outside_sandbox(dir, config_path)
    assert_equal(urls.count, urls.select{|url| broken_url_eventually? url }.count)
    assert_all_assets_have_upload_status(csv, ['audio'], 'no')
  end

  def test_tp_finish_on_audio_files_with_sftp
    skip_if_no_sftp_credentials('tp-finish sftp test')
    with_temp_readymade_project do |dir|
      config_path = self.config_path(dir)
      tp_finish_on_audio_files_with(dir, config_path)
    end 
  end

  def test_tp_finish_on_audio_files_with_s3
    skip_if_no_s3_credentials('tp-finish sftp test')
    with_temp_readymade_project do |dir|
      config = config_from_dir(dir)
      config.to_hash.delete('sftp')
      config_path = write_config(config, dir)
      reconfigure_readymade_project_in(config_path)
      tp_finish_on_audio_files_with(dir, config_path)
    end
  end

  def test_tp_finish_on_amazon_hits
    skip_if_no_amazon_credentials('tp-finish Amazon test')
    skip_if_no_upload_credentials('tp-finish Amazon test')
    with_temp_readymade_project do |dir|
      tp_assign(dir)
      project = temp_tp_dir_project(dir)
      csv = project.local.file('data', 'assignment.csv').as(:csv)
      sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
      assert_all_assets_have_upload_status(sandbox_csv, ['assignment'], 'yes')
      assert_all_assets_have_upload_status(csv, ['audio'], 'yes')
      setup_amazon(dir)
      results = Typingpool::Amazon::HIT.all_for_project(project.local.id)
      refute_empty(results)
      tp_finish(dir)
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
      refute(File.exists? sandbox_csv)
      assert_all_assets_have_upload_status(csv, ['audio'], 'no')
    end #with_temp_readymade_project do...
  end

  def test_tp_finish_with_missing_files
    skip_if_no_amazon_credentials('tp-finish missing files test')
    skip_if_no_upload_credentials('tp-finish missing files test')
    with_temp_readymade_project do |dir|
      project = nil
      simulate_failed_audio_upload_in(config_path(dir))
      tp_make(dir)
      begin
        project = temp_tp_dir_project(dir)
        assignments = project.local.file('data', 'assignment.csv').as(:csv).read
        urls = assignments.map{|assignment| assignment['audio_url'] }
        assert_equal(urls.count, urls.select{|url| working_url_eventually? url }.count)
        bogus_url = urls.first.sub(/\.mp3/, '.foo.mp3')
        refute_equal(urls.first, bogus_url)
        refute(working_url? bogus_url)
        bogus_assignment = assignments.first.dup
        bogus_assignment['audio_url'] = bogus_url
        assignments.insert(1, bogus_assignment)
        project.local.file('data', 'assignment.csv').as(:csv).write(assignments)
        assignments = project.local.file('data', 'assignment.csv').as(:csv).read
        refute(working_url? assignments[1]['audio_url'])
      ensure
        tp_finish_outside_sandbox(dir)
      end #begin
      urls = project.local.file('data', 'assignment.csv').as(:csv).map{|assignment| assignment['audio_url'] }
      assert_equal(urls.count, urls.select{|url| broken_url_eventually? url }.count)
    end #with_temp_readymade_project do...
  end

  def test_abort_on_config_mismatch
    skip_if_no_s3_credentials('tp-finish abort on config mismatch test')
    with_temp_readymade_project do |dir|
      config = config_from_dir(dir)
      good_config_path = setup_s3_config(dir, config, '.config_s3_good')
      reconfigure_readymade_project_in(good_config_path)
      simulate_failed_audio_upload_in(good_config_path)
      assert(config.amazon.bucket)
      new_bucket = 'configmismatch-test'
      refute_equal(new_bucket, config.amazon.bucket)
      config.amazon.bucket = new_bucket
      bad_config_path = setup_s3_config(dir, config, '.config_s3_bad')
      exception = assert_raises(Typingpool::Error::Shell) do
        tp_finish_outside_sandbox(dir, bad_config_path)
      end #assert_raises...
      assert_match(/\burls don't look right\b/i, exception.message)
    end #with_temp_readymade_project do...
  end

end #TestTpFinish
