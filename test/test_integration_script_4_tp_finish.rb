#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'audibleturk'
require 'audibleturk/test'

class TestTpFinish < Audibleturk::Test::Script
  def test_tp_finish_on_audio_files
    skip_if_no_amazon_credentials('tp-collect audio test')
    in_temp_tp_dir do |dir|
      tp_make(dir)
      project = temp_tp_dir_project(dir)
      urls = project.local.read_csv('assignment').map{|assignment| assignment['url'] }
      assert(not(urls.empty?))
      assert_equal(urls.size, urls.select{|url| working_url? url}.size)
      assert_nothing_raised do
        tp_finish(dir)
      end
      assert_empty(urls.select{|url| working_url? url })
    end #in_temp_tp_dir
  end

  def test_tp_finish_on_amazon_hits
    skip_if_no_amazon_credentials('tp-collect Amazon test')
    in_temp_tp_dir do |dir|
      tp_make(dir)
      tp_assign(dir)
      project = temp_tp_dir_project(dir)
      setup_amazon(dir)
      results = Audibleturk::Amazon::Result.all_for_project(project.local.id, amazon_result_params)
      assert(not(results.empty?))
      assert_nothing_raised do
        tp_finish(dir)
      end
      assert_empty(Audibleturk::Amazon::Result.all_for_project(project.local.id, amazon_result_params))
      results.each do |result|
        #The original HIT might be gone, or there and marked
        #'disposed', depending whether Amazon has swept the server for
        #dead HITs yet
        begin 
          hit = RTurk::Hit.find(result.hit_id)
          assert_match(hit.status, /^dispos/i)
        rescue RTurk::InvalidRequest => exception
          assert_match(exception.message, /HITDoesNotExist/i)
        end
      end
    end #in_temp_tp_dir
  end
end #TestTpFinish
