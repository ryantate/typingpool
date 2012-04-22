#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool/test'
require 'fileutils'

class CollectProjectFixtureGen3 < Typingpool::Test::Script
  def test_populate_fixture2
    fixture_path = File.join(fixtures_dir, 'vcr', 'tp-collect-2')
    tp_collect_with_fixture(fixture_project_dir('tp_collect_project_temp'), fixture_path)
    assert(File.exists?("#{fixture_path}.yml"))
    add_goodbye_message("Second tp-collect recorded. Please complete and approve THREE more assignments and run make_tp_collect_fixture_4.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n...and then approve them at\nhttps://requestersandbox.mturk.com/mturk/manageHITs?hitSortType=CREATION_DESCENDING&%2Fsort.x=11&%2Fsort.y=7")
  end
end
