#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

fixture_name =  'tp-review-3'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
transcripts_dir = File.join(fixtures_dir, 'tp_review2_projects_temp')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r a r s s r a a s a q ), true)

output[:status].to_i == 0 or abort "Bad exit code on first run: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
output[:out] or abort "No STDOUT from tp-review, did not collect as required"
review_count = split_reviews(output[:out]).count - 1
review_count == 12 or abort "Expected 12 reviews from tp-review, got #{review_count}"
project_title = Dir.entries(transcripts_dir).reject{|entry| entry.match(/^\./) }
project = project_title.map{|title| Typingpool::Project.new(title, Typingpool::Config.file(config_path(transcripts_dir))) }
project_transcript_count(project[0], 'sandbox-assignment.csv') == 2 or abort "Unexpected number of transcripts in project 1 after run 1: #{project_transcript_count(project[0], 'sandbox-assignment.csv')} instead of 2"
project_transcript_count(project[1], 'sandbox-assignment.csv') == 3 or abort "Unexpected number of transcripts in project 2 after run 1: #{project_transcript_count(project[1], 'sandbox-assignment.csv')} instead of 3"

sleep 10
fixture_name = 'tp-review-4'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r s a), true)
output[:status].to_i == 0 or abort "Bad exit code on second run: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
output[:out] or abort "No STDOUT from tp-review, did not collect as required"
review_count = split_reviews(output[:out]).count - 1
review_count == 4 or abort "Expected 4 reviews from tp-review, got #{review_count}"
project_transcript_count(project[0], 'sandbox-assignment.csv') == 3 or abort "Unexpected number of transcripts in project 1 after run 2: #{project_transcript_count(project[0], 'sandbox-assignment.csv')} instead of 3"
project_transcript_count(project[1], 'sandbox-assignment.csv') == 4 or abort "Unexpected number of transcripts in project 2 after run 2: #{project_transcript_count(project[1], 'sandbox-assignment.csv')} instead of 4"


STDERR.puts "Waiting 6 minutes to make auto-approval fixture, please stand by..."
sleep 60*6
fixture_name = 'tp-review-5'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(q), true)
output[:status].to_i == 0 or abort "Bad exit code on third run: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project_transcript_count(project[1], 'sandbox-assignment.csv') == 5 or abort "Unexpected number of transcripts in project 2 after run 3: #{project_transcript_count(project[1], 'sandbox-assignment.csv')} instead of 5"


project_title.each do |title|
  tp_finish(transcripts_dir, config_path(transcripts_dir), title)
end
FileUtils.remove_entry_secure(File.join(fixtures_dir, 'tp_review2_projects_temp'), :secure => true)
STDERR.puts "All done!"
