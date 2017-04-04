#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

transcripts_dir = make_fixture_transcripts_dir('tp_review2_projects_temp')
write_testing_config_for_transcripts_dir(transcripts_dir, self.config)
projects = [
  {title: project_default[:title], fixture_prefix: 'tp_review2a_'},
  {title: "Second #{project_default[:title]}", fixture_prefix: 'tp_review2b_'}
]
begin
  projects.each do |project| 
    tp_make(transcripts_dir, config_path(transcripts_dir), 'mp3', false, '--title', project[:title])
    tp_assign(transcripts_dir, config_path(transcripts_dir), project[:title])
  end
rescue
  FileUtils.remove_entry_secure(transcripts_dir)
  raise
end
#copy key files over to permanent locations within fixture dir
projects.each do |project|
    with_fixtures_in_project_dir(project[:fixture_prefix], File.join(transcripts_dir, project[:title])) do |source_fixture_path, project_fixture_path|
      FileUtils.cp(project_fixture_path, source_fixture_path)
    end
  end #each do |project|

STDERR.puts "Two temp projects assigned in Mechanical Turk sandbox. Complete TWELVE (12) assignments and run make_tp_review_fixture_4.rb. Check for assignments at"
STDOUT.puts "https://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups"
STDERR.puts "\n"
