#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

dir = make_fixture_project_dir('tp_review_project_temp')
make_transcripts_dir_config(dir, self.config)
begin
  tp_make(dir)
  tp_assign(dir)
rescue
  FileUtils.remove_entry_secure(dir)
  raise
end
#copy key files over to permanent locations within fixture dir
with_fixtures_in_transcripts_dir(dir, 'tp_review_') do |fixture_path, project_path|
  FileUtils.cp(project_path, fixture_path)
end
STDERR.puts "Temp project assigned in Mechanical Turk sandbox. Complete SIX assignments and run make_tp_review_fixture_2.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n"

