#!/usr/bin/env ruby

require 'optparse'
require 'uri'
require 'audibleturk'

options = {}
OptionParser.new do |opts|
  options[:banner] = opts.banner = "USAGE: at-remove PROJECTNAME --local | --remote | --all"
  opts.on('-l', '--local', 'Permanently delete the local project directory') do
    options[:local] = true
  end
  opts.on('-r', '--remote', 'Delete the associated audio files on the remote server') do
    options[:remote] = true
  end
  opts.on('-a', '--all', 'Same as --local --remote') do
    options[:local] = true
    options[:remote] = true
  end
  opts.on('--help', 'Display this screen') do
    puts opts
    exit
  end
end.parse!

project_name = ARGV[0] or abort "#{options[:banner]}\nat-remove --help for more.\n"
project = Audibleturk::Project.new(project_name) or abort "No such project '#{project_name}'\n"
(options[:local] || options[:remote]) or abort "Did not specify what to remove (--remote or --local or --all).\nat-remove --help for more.\n"

if options[:remote]
  project.www.remove(project.local.csv('assignment').collect{|row_hash| File.basename(URI.parse(row_hash['url']).path) })
end

if options[:local]
  path = project.local.path
  Audibleturk::Project::Local.ours?(path) or abort "Contents of dir #{path} look wrong"
  FileUtils.rm_r(path, :secure => true)
end
