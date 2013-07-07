#!/usr/bin/env ruby

require 'rake'
require 'rake/testtask'

task :default => [:test]

desc "Run all tests"
task :test => [:test_unit, :test_integration]

desc "Run unit tests"
Rake::TestTask.new('test_unit') do |t|
  t.pattern = 'test/test_unit*'
end

desc "Run integration tests"
Rake::TestTask.new('test_integration') do |t|
  t.pattern = 'test/test_integration_script*'
end
