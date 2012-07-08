#!/usr/bin/env ruby

require 'rake'
require 'rake/testtask'

task :default => [:test]

desc "Run all tests"
Rake::TestTask.new('test') do |t|
  t.test_files = FileList[ 
                          (1..6).map{|n| "test/test_integration_script_#{n}*" }
                         ]
end

desc "Run unit tests"
Rake::TestTask.new('test_unit') do |t|
  t.test_files = FileList[
                          'test/test_unit*'
                         ]
end
