#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

dir = make_fixture_transcripts_dir('tp_review_project_temp')
write_testing_config_for_transcripts_dir(dir, self.config)
begin
  tp_make(dir)
  tp_assign(dir, config_path(dir), project_default[:title], '--approval', '5m')
rescue
  FileUtils.remove_entry_secure(dir)
  raise
end
#copy key files over to permanent locations within fixture dir
with_fixtures_in_project_dir('tp_review_', File.join(dir, project_default[:title])) do |source_fixture_path, project_fixture_path|
  FileUtils.cp(project_fixture_path, source_fixture_path)
end
STDERR.puts "Temp project assigned in Mechanical Turk sandbox. Complete SIX assignments and run make_tp_review_fixture_2.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n"

