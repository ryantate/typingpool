#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

fixture_name =  'tp-review-1'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
transcripts_dir = File.join(fixtures_dir, 'tp_review_project_temp')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r a r s q ), true, project_default[:title])

output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"

fixture_name = 'tp-review-2'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
output = tp_review_with_fixture(transcripts_dir, fixture_name, %w(a r), true, project_default[:title])
output[:status].to_i == 0 or abort "Bad exit code: #{output[:status]} err: #{output[:err]}"
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
tp_finish(transcripts_dir)
FileUtils.remove_entry_secure(File.join(fixtures_dir, 'tp_review_project_temp'), :secure => true)
STDERR.puts "All done!"
