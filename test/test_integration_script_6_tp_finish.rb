#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpFinish < Typingpool::Test::Script
  def tp_finish_on_audio_files_with(dir, config_path)
    skip_if_no_amazon_credentials('tp-finish audio test')
    skip_if_no_upload_credentials('tp-finish audio test')
    tp_make(dir, config_path)
    project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path))
    csv = project.local.file('data', 'assignment.csv').as(:csv)
    urls = csv.map{|assignment| assignment['audio_url'] }
    refute_empty(urls)
    assert_all_assets_have_upload_status(csv, ['audio'], 'yes')
    sleep 3 #pause before checking URLs so remote server has time to fully upload
    assert_equal(urls.size, urls.select{|url| working_url? url}.size)
    assert_nothing_raised do
      tp_finish_outside_sandbox(dir, config_path)
    end
    sleep 3 #pause before checking URLs so remote server has time to fully delete 
    assert_empty(urls.select{|url| working_url? url })
    assert_all_assets_have_upload_status(csv, ['audio'], 'no')
  end

  def test_tp_finish_on_audio_files_with_sftp
    skip_if_no_sftp_credentials('tp-finish sftp test')
    in_temp_tp_dir do |dir|
      config_path = self.config_path(dir)
      tp_finish_on_audio_files_with(dir, config_path)
    end 
  end

  def test_tp_finish_on_audio_files_with_s3
    skip_if_no_s3_credentials('tp-finish sftp test')
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      config.to_hash.delete('sftp')
      config_path = write_config(config, dir)
      tp_finish_on_audio_files_with(dir, config_path)
    end
  end

  def test_tp_finish_on_amazon_hits
    skip_if_no_amazon_credentials('tp-finish Amazon test')
    skip_if_no_upload_credentials('tp-finish Amazon test')
    in_temp_tp_dir do |dir|
      tp_make(dir)
      tp_assign(dir)
      project = temp_tp_dir_project(dir)
      sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
      assert_all_assets_have_upload_status(sandbox_csv, ['audio', 'assignment'], 'yes')
      setup_amazon(dir)
      results = Typingpool::Amazon::HIT.all_for_project(project.local.id)
      refute_empty(results)
      assert_nothing_raised do
        tp_finish(dir)
      end
      assert_empty(Typingpool::Amazon::HIT.all_for_project(project.local.id))
      results.each do |result|
        #The original HIT might be gone, or there and marked
        #'disposed', depending whether Amazon has swept the server for
        #dead HITs yet
        begin 
          hit = RTurk::Hit.find(result.id)
          assert_match(hit.status, /^dispos/i)
        rescue RTurk::InvalidRequest => exception
          assert_match(exception.message, /HITDoesNotExist/i)
        end #begin
      end #results.each...
      refute(File.exists? sandbox_csv)
      assert_all_assets_have_upload_status(project.local.file('data', 'assignment.csv').as(:csv), ['audio'], 'no')
    end #in_temp_tp_dir
  end

  def test_tp_finish_with_missing_files
    skip_if_no_amazon_credentials('tp-finish missing files test')
    skip_if_no_upload_credentials('tp-finish missing files test')
    in_temp_tp_dir do |dir|
      project = nil
      tp_make(dir)
      begin
        project = temp_tp_dir_project(dir)
        assignments = project.local.file('data', 'assignment.csv').as(:csv).read
        urls = assignments.map{|assignment| assignment['audio_url'] }
        assert_empty(urls.reject{|url| working_url? url })
        bogus_url = urls.first.sub(/\.mp3/, '.foo.mp3')
        refute_equal(urls.first, bogus_url)
        refute(working_url? bogus_url)
        bogus_assignment = assignments.first.dup
        bogus_assignment['audio_url'] = bogus_url
        assignments.insert(1, bogus_assignment)
        project.local.file('data', 'assignment.csv').as(:csv).write(assignments)
        assert_equal(1, project.local.file('data', 'assignment.csv').as(:csv).reject{|assignment| working_url? assignment['audio_url'] }.count)
      ensure
        tp_finish_outside_sandbox(dir)
      end #begin
      assert_empty(project.local.file('data', 'assignment.csv').as(:csv).select{|assignment| working_url? assignment['audio_url'] })
    end #in_temp_tp_dir...
  end

def test_abort_on_config_mismatch
  skip_if_no_s3_credentials('tp-finish abort on config mismatch test')
  in_temp_tp_dir do |dir|
    config = config_from_dir(dir)
    good_config_path = setup_s3_config(dir, config, '.config_s3_good')
    tp_make(dir, good_config_path)
    begin
      assert(config.amazon.bucket)
      new_bucket = 'configmismatch-test'
      refute_equal(new_bucket, config.amazon.bucket)
      config.amazon.bucket = new_bucket
      bad_config_path = setup_s3_config(dir, config, '.config_s3_bad')
      exception = assert_raises(Typingpool::Error::Shell) do
        tp_finish_outside_sandbox(dir, bad_config_path)
      end #assert_raises...
      assert_match(exception.message, /\burls don't look right\b/i)
    ensure
      tp_finish_outside_sandbox(dir, good_config_path)
    end #begin
  end #in_temp_tp_dir do...

end

end #TestTpFinish
