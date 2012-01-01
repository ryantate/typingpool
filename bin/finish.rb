#!/usr/bin/env ruby

require 'optparse'
require 'uri'
require 'audibleturk'

options = {
  :config => Audibleturk::Config.file
}
OptionParser.new do |commands|
  options[:banner] = commands.banner = "USAGE: #{File.basename($PROGRAM_NAME)} PROJECT [--config PATH] [--sandbox]\n"
  commands.on('--config=PATH', "Default: #{Audibleturk::Config.default_file}.", " A config file") do |path|
    File.exists?(File.expand_path(path)) && File.file?(File.expand_path(path)) or abort "No such file #{path}"
    options[:config] = Audibleturk::Config.file(path)
  end
  commands.on('--sandbox', "Test in Mechanical Turk's sandbox") do
    options[:sandbox] = true
  end
  commands.on('--help', 'Display this screen') do
    $stderr.puts commands 
    exit
  end
end.parse!
options[:banner] += "`#{File.basename($PROGRAM_NAME)} --help` for more information.\n"
project_name_or_path = ARGV[0] or abort options[:banner]

project = Audibleturk::Project.new(File.basename(project_name_or_path), options[:config])
project_local = project.local(File.dirname(project_name_or_path)) or abort "No such project '#{project_name_or_path}'\n"
project_local.id or abort "Can't find project id in #{project_local.path}"

$stderr.puts "Removing from Amazon..."
Audibleturk::Amazon.setup(:sandbox => options[:sandbox], :key => options[:config].param['aws']['key'], :secret => options[:config].param['aws']['secret'])
begin
  Audibleturk::Amazon::Result.all_for_project(project_local.id).each{|result| result.remove_hit }
rescue Audibleturk::Error::Amazon::UnreviewedContent => e
  abort "Can't finish: One or more transcriptions are submitted but unprocessed (#{e})"
end

$stderr.puts "Removing from #{project.www.host}..."
project.www.remove(project_local.csv('assignment').collect{|row_hash| File.basename(URI.parse(row_hash['url']).path) })

