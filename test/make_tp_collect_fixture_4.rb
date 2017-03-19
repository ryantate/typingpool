#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/utility/test/script'
require 'fileutils'

include Typingpool::Utility::Test::Script

fixture_name = 'tp-collect-3'
transcripts_dir = fixture_project_dir('tp_collect_project_temp')
tp_collect_with_fixture(transcripts_dir, fixture_name, true)
fixture_path = File.join(vcr_dir, fixture_name + '.yml')
File.exists? fixture_path or abort "Can't find fixture as expected at #{fixture_path}"
(Time.now - File.ctime(fixture_path)) < 60 or abort "Fixture file does not appear newly created at #{fixture_path}"
project = transcripts_dir_project(transcripts_dir)
transcript_count = project_transcript_count(project, 'sandbox-assignment.csv')
transcript_count == 5 or abort "Unexpected number of transcripts in project: #{transcript_count}. Did you wait five full minutes after submitting the assignments?"

STDERR.puts("Third tp-collect recorded. Fixtures for tp-collect testing successfully generated!")


