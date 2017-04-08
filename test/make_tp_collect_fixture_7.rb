#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

fixture_name='tp-review-8'
transcripts_dir = File.join(fixtures_dir, 'tp_review3_project_temp')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(q), true)
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(transcripts_dir)))
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 3 or abort "Unexpected number of transcripts added to tp-review project: #{transcript_count}"

STDERR.puts("Fifth tp-collect recorded. Please complete TWO more assignments but ONLY APPROVE ONE. Ignore the other. Wait 5 minutes and then run make_tp_collect_fixture_8.rb. Check for assignments at\nhttps://workersandbox.mturk.com/mturk/searchbar?minReward=0.00&searchWords=typingpooltest&selectedSearchType=hitgroups\n...and then approve them at\nhttps://requestersandbox.mturk.com/mturk/manageHITs?hitSortType=CREATION_DESCENDING&%2Fsort.x=11&%2Fsort.y=7")
