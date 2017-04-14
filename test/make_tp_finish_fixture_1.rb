#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

transcripts_dir = make_fixture_transcripts_dir('tp_finish_project_temp')
write_testing_config_for_transcripts_dir(transcripts_dir, reconfigure_for_s3(self.config))

begin
  tp_make(transcripts_dir)
  tp_assign(transcripts_dir, config_path(transcripts_dir), project_default[:title])
rescue
  FileUtils.remove_entry_secure(transcripts_dir)
  raise
end

#copy key files over to permanent locations within fixture dir
with_fixtures_in_project_dir('tp_finish_4_', File.join(transcripts_dir, project_default[:title])) do |source_fixture_path, project_fixture_path|
  FileUtils.cp(project_fixture_path, source_fixture_path)
end
STDERR.puts "Temp project assigned in Mechanical Turk sandbox. Complete FOUR assignments and run make_tp_finish_fixture_2.rb. Check for assignments at"
STDOUT.puts "https://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n"
