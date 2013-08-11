#!/usr/bin/env ruby

require 'rake'
require 'rake/testtask'

task :default => [:test]

desc "Run all tests (mocking network calls)"
task :test => ['test-unit'.to_sym, 'test-integration'.to_sym]

desc "Run all tests (with live network calls)"
task 'test-live'.to_sym => ['test-unit-live'.to_sym, 'test-integration-live'.to_sym]


unit_test_file_pattern = 'test/test_unit*'
desc "Run unit tests (mocking network calls)"
Rake::TestTask.new('test-unit') do |t|
  t.pattern = unit_test_file_pattern
end

desc "Run unit tests (with live network calls)"
Rake::TestTask.new('test-unit-live') do |t|
  t.pattern = unit_test_file_pattern
  t.options = '--live'
end


integration_test_file_pattern = 'test/test_integration_script*'
desc "Run integration tests (mocking network calls)"
Rake::TestTask.new('test-integration') do |t|
  t.pattern = integration_test_file_pattern
end

desc "Run integration tests (with live network calls)"
Rake::TestTask.new('test-integration-live') do |t|
  t.pattern = integration_test_file_pattern
  t.options = '--live'
end

