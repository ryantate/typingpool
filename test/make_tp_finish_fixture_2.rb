#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

transcripts_dir = File.join(fixtures_dir, 'tp_finish_project_temp')

fixture_name =  'tp_finish_9'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r q), true, project_default[:title])
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(transcripts_dir)))
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 1 or abort "Unexpected number of transcripts in project after first run: #{transcript_count}"

STDERR.puts "Initial step recorded. Please manually approve ONE assignment at"
STDOUT.puts "https://requestersandbox.mturk.com/mturk/manageHITs?hitSortType=CREATION_DESCENDING&%2Fsort.x=11&%2Fsort.y=7"
STDERR.puts "...and run make_tp_finish_fixture_3.rb"
