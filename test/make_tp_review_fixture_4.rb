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

output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
output[:out] or abort "No STDOUT from tp-review, did not collect as required"
review_count = split_reviews(output[:out]).count
review_count >= 12 or abort "Expected 12 reviews from tp-review, got #{review_count}"

sleep 10
fixture_name = 'tp-review-4'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r a a a), true)
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
output[:out] or abort "No STDOUT from tp-review, did not collect as required"
review_count = split_reviews(output[:out]).count
review_count >= 1 or abort "Expected 1 or more reviews from tp-review, got #{review_count}"


Dir.entries(transcripts_dir).each do |entry|
  #tp_finish both projects by pulling their titles from their folder names
  next if entry.match(/^\./)
  tp_finish(transcripts_dir, config_path(transcripts_dir), entry)
end
FileUtils.remove_entry_secure(File.join(fixtures_dir, 'tp_review2_projects_temp'), :secure => true)
STDERR.puts "All done!"
