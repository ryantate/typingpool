#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpFinish < Typingpool::Test::Script
  def tp_finish_on_audio_files_with(dir, config_path)
    skip_if_no_amazon_credentials('tp-collect audio test')
    skip_if_no_upload_credentials('tp-collect audio test')
    tp_make(dir, config_path)
    project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path))
    urls = project.local.csv('data', 'assignment.csv').map{|assignment| assignment['audio_url'] }
    assert(not(urls.empty?))
    assert_equal(urls.size, urls.select{|url| working_url? url}.size)
    assert_nothing_raised do
      tp_finish(dir, config_path)
    end
    assert_empty(urls.select{|url| working_url? url })
  end

  def test_tp_finish_on_audio_files
    in_temp_tp_dir do |dir|
      config_path = self.config_path(dir)
      tp_finish_on_audio_files_with(dir, config_path)
    end
  end

  def test_tp_finish_on_audio_files_with_s3
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      config.to_hash.delete('sftp')
      config_path = write_config(config, dir)
      tp_finish_on_audio_files_with(dir, config_path)
    end
  end

  def test_tp_finish_on_amazon_hits
    skip_if_no_amazon_credentials('tp-collect Amazon test')
    skip_if_no_upload_credentials('tp-collect Amazon test')
    in_temp_tp_dir do |dir|
      tp_make(dir)
      tp_assign(dir)
      project = temp_tp_dir_project(dir)
      setup_amazon(dir)
      results = Typingpool::Amazon::HIT.all_for_project(project.local.id)
      assert(not(results.empty?))
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
        end
      end
    end #in_temp_tp_dir
  end
end #TestTpFinish
