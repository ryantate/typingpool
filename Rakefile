#!/usr/bin/env ruby

require 'rake'
require 'rake/testtask'

task :default => [:test]

desc "Run all tests"
Rake::TestTask.new('test') do |t|
  t.test_files = FileList[ 
                          'test/test_unit*',
                          (1..5).map{|n| "test/test_integration_script_#{n}*" }
                         ]
end
