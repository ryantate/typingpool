#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

transcripts_dir = File.join(fixtures_dir, 'tp_finish_project_temp')

fixture_name =  'tp_finish_10'
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
out, err = tp_finish_inside_sandbox_with_vcr(transcripts_dir, fixture_name, config_path(transcripts_dir), false, true, %w(s a))
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project = Typingpool::Project.new(project_default[:title], Typingpool::Config.file(config_path(transcripts_dir)))
transcript_count = project_transcript_count(project, 'old-sandbox-assignment.csv')
transcript_count == 2 or abort "Unexpected number of transcripts in project: #{transcript_count}. Did you remember to manually approve one HIT?"
err.match(/not been added/) or abort "tp-finish did not seem to notice the approved, unadded HIT"
err.match(/unreviewed submission/) or abort "tp-finish did not seem to notice the submitted, unreviewed HIT"
tp_finish(transcripts_dir, config_path(transcripts_dir), project_default[:title], nil, '--force')
FileUtils.remove_entry_secure(transcripts_dir, :secure => true)
STDERR.puts "All done!"

