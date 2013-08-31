#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'
require 'fileutils'

class MakeAndAssignProject < Typingpool::Test::Script
  def test_prep_for_fixture
    dir = make_fixture_project_dir('tp_collect_project_temp')
    make_transcripts_dir_config(dir, self.config)
    begin
      tp_make(dir)
      tp_assign(dir)
    rescue
      FileUtils.remove_entry_secure(dir)
      raise
    end
    #copy key files over to permanent locations within fixture dir
    with_fixtures_in_transcripts_dir(dir, 'tp_collect_') do |fixture_path, project_path|
      FileUtils.cp(project_path, fixture_path)
    end
    add_goodbye_message("Temp project assigned in Mechanical Turk sandbox. Complete and approve TWO assignments and run make_tp_collect_fixture_2.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n...and then approve them at\nhttps://requestersandbox.mturk.com/mturk/manageHITs?hitSortType=CREATION_DESCENDING&%2Fsort.x=11&%2Fsort.y=7")
  end
end #MakeAndAssignProject
