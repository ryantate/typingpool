#!/usr/bin/env ruby

require 'optparse'
require 'uri'
require 'typingpool'
require 'set'

options = {
  :config => Typingpool::Config.file
}
OptionParser.new do |commands|
  options[:banner] = commands.banner = "USAGE: #{File.basename($PROGRAM_NAME)} PROJECT | --dead\n  [--sandbox]\n  [--config PATH]\n"
  commands.on('--dead', "Remove ALL expired and rejected results, regardless of project.","  Use in leiu of PROJECT.", "  Removes only Mechanical Turk HITs, not remote audio files") do
    options[:dead] = true
  end
  commands.on('--sandbox', "Test in Mechanical Turk's sandbox") do
    options[:sandbox] = true
  end
  commands.on('--config=PATH', "Default: #{Typingpool::Config.default_file}.", " A config file") do |path|
    File.exists?(File.expand_path(path)) && File.file?(File.expand_path(path)) or abort "No such file #{path}"
    options[:config] = Typingpool::Config.file(path)
  end
  commands.on('--help', 'Display this screen') do
    STDERR.puts commands 
    exit
  end
end.parse!
options[:banner] += "`#{File.basename($PROGRAM_NAME)} --help` for more information.\n"

project_name_or_path = ARGV[0] 
project_name_or_path = nil if project_name_or_path.to_s.match(/^\s+$/)
abort "Can't specify both PROJECT and --dead" if project_name_or_path && options[:dead]
abort "No PROJECT specified (and no --dead option)\n#{options[:banner]}" if not(project_name_or_path || options[:dead])

project=nil
#Error checking on project info first
if project_name_or_path
  project_path = nil
  if File.exists?(project_name_or_path)
    project_path = project_name_or_path
    options[:config].transcripts = File.dirname(project_name_or_path)
  else
    project_path = "#{options[:config].transcripts}/#{project_name_or_path}"
  end
  project = Typingpool::Project.new(File.basename(project_path), options[:config])
  project.local or abort "No such project '#{project_name_or_path}'\n"
  project.local.id or abort "Can't find project id in #{project.local.path}"
end

Typingpool::Amazon.setup(:sandbox => options[:sandbox], :config => options[:config])
STDERR.puts "Removing from Amazon"
STDERR.puts "  Collecting all results"
#Set up result set, depending on options
results = nil
if project
  results = Typingpool::Amazon::HIT.all_for_project(project.local.id)
elsif options[:dead]
  results = Typingpool::Amazon::HIT.all.select do |result|
    dead = ((result.full.expired_and_overdue? || result.rejected?) && result.ours?)
    result.to_cache
    dead
  end
end

#Remove the results from Mechanical Turk
fails = []
results.each do |result| 
  STDERR.puts "  Removing HIT #{result.id} (#{result.full.status})"
  begin
    result.remove_from_amazon 
  rescue Typingpool::Error::Amazon::UnreviewedContent => e
    fails.push(e)
  else
    STDERR.puts "  Removing from local cache"
    Typingpool::Amazon::HIT.delete_cache(result.id)
  end
end
if not (fails.empty?)
  STDERR.puts "  Removed " + (results.size - fails.size) + " HITs from Amazon"
  abort "#{fails.size} transcriptions are submitted but unprocessed (#{fails.join('; ')})"
end
#Remove the remote audio files associated with the results and update the assignment.csb associated with the project
if project 
  assignments = project.local.csv('data', 'assignment.csv').read
  deleting = assignments.map{|assignment| assignment['assignment_url'] }.select{|url| url }
  if project.local.audio_is_on_www
    deleting << assignments.map{|assignment| assignment['audio_url'] }
  end
  if not(deleting.empty?)
    STDERR.puts "Removing mp3s and assignment HTML from #{project.remote.host}"
    begin
      project.remote.remove_urls(deleting.flatten)
    rescue Typingpool::Error::File::Remote => e
      abort "Can't remove remote audio files: #{e}"
    end #begin
    STDERR.puts "  Removed #{deleting.size}  files from #{project.remote.host}"
    if project.local.audio_is_on_www
      project.local.delete_audio_is_on_www
    end
  end #if not(deleting.empty?)
  project.local.csv('data', 'assignment.csv').each! do |assignment|
    assignment.delete('assignment_url')
    if assignment['hit_expires_at'].to_s.match(/\S/)
      #we don't delete the hit_id because we may need it when building
      #the transcript (if the HIT was approved)
      %w(hit_expires_at hit_assignments_duration).each{|key| assignment.delete(key) }
    end
  end
end #if project
