#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

transcripts_dir = File.join(fixtures_dir, 'tp_review_project_temp')

fixture_name =  'tp-review-1'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r a r s q ), true, project_default[:title])
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(transcripts_dir)))
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 2 or abort "Unexpected number of transcripts in project after first run: #{transcript_count}"

fixture_name = 'tp-review-2'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a q), true, project_default[:title])
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 3 or abort "Unexpected number of transcripts in project after second run: #{transcript_count}"


STDERR.puts "Waiting 6 minutes to make auto-approval fixture, please stand by..."
sleep 60*6


fixture_name = 'tp-review-6'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(q), true, project_default[:title])
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 4 or abort "Unexpected number of transcripts in project after third run: #{transcript_count}"

tp_finish(transcripts_dir)
FileUtils.remove_entry_secure(File.join(fixtures_dir, 'tp_review_project_temp'), :secure => true)
STDERR.puts "All done!"

