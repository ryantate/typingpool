#!/usr/bin/env ruby

require 'audibleturk'
require 'audibleturk/test'
require 'fileutils'

class MakeAndAssignProject < Audibleturk::Test::Script
  def test_prep_for_fixture
    dir = make_tp_collect_fixture_project_dir
    setup_temp_tp_dir(dir)
    begin
      tp_make(dir)
      tp_assign(dir)
    rescue
      FileUtils.remove_entry_secure(dir)
      raise
    end
    add_goodbye_message("Temp project assigned in MT sandbox. Please complete and approve two assignments and run make_tp_collect_fixture_2.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n...and then approve them at\nhttps://requestersandbox.mturk.com/mturk/manageHITs?hitSortType=CREATION_DESCENDING&%2Fsort.x=11&%2Fsort.y=7")
  end
end #MakeAndAssignProject
