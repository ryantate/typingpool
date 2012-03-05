#!/usr/bin/env ruby

require 'rake'
require 'rake/testtask'

task :default => [:test]

desc "Run all tests"
Rake::TestTask.new('test') do |t|
  t.pattern = 'test/test_*.rb'
end
