#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'
require 'optparse'

options = {
  :url_at => 'typingpool_url',
  :id_at => 'typingpool_project_id',
  :config => Audibleturk::Config.file
}

OptionParser.new do |commands|
  options[:banner] = commands.banner = "USAGE: #{File.basename($PROGRAM_NAME)} [--config='#{Audibleturk::Config.default_file}'] [--sandbox]\n [--url_at=#{options[:url_at]}] [--id_at=#{options[:id_at]}]\n"
  commands.on('--sandbox', "Collect from the Mechanical Turk test sandbox") do
    options[:sandbox] = true
  end
  commands.on('--url_at=PARAM', "Default: #{options[:url_at]}.", " Name of the HTML form field for audio URLs") do |url_at|
    options[:url_at] = url_at
  end
  commands.on('--id_at=PARAM', "Default: #{options[:id_at]}.", " Name of the HTML form field for project IDs") do |id_at|
    options[:id_at] = id_at
  end
  commands.on('--config=PATH', "Default: #{Audibleturk::Config.default_file}.", " A config file") do |config|
    path = File.expand_path(config)
    File.exists?(path) && File.file?(path) or abort "No such file #{path}"
    options[:config] = Audibleturk::Config.file(config)
  end
  commands.on('--help', "Display this screen") do
    $stderr.puts commands
    exit
  end
end.parse!

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}

$stderr.puts "Collecting results from Amazon"
Audibleturk::Amazon.setup(:sandbox => options[:sandbox], :config => options[:config])
results = Audibleturk::Amazon::Result.all_approved(:url_at => options[:url_at], :id_at => options[:id_at])
#Only pay attention to results that have a local folder waiting to receive them:
projects = {}
need = {}
$stderr.puts "Looking for local project folders to receive results" unless results.empty?
results.each do |result| 
  key = result.transcription.project #project id
  if need[key]
    need[key].push(result)
  elsif need[key] == false
    next
  else
    need[key] = false
    project = Audibleturk::Project.new(result.transcription.title, options[:config])
    #folder must exist
    project.local or next;
    #transcript must not be complete
    next if File.exists?("#{project.local.path}/#{filename[:done]}")
    #folder id must match incoming id
    next if project.local.id != result.transcription.project
    projects[key] = project
    need[key] = [result]
  end
end
template = nil
projects.each do |key, project|
  results_by_url = Hash[ *need[key].collect{|result| [result.url, result] }.flatten ]
  assignments = project.local.read_csv('assignment')
  assignments.each do |assignment|
    result = results_by_url[assignment['url']] or next
    next if assignment['transcription']
    assignment['transcription'] = result.transcription.body
    assignment['worker'] = result.transcription.worker
    assignment['hit_id'] result.hit_id
  end
  project.local.write_csv('assignment', assignments)
  transcription_chunks = project.local.read_csv('assignment').select{|assignment| assignment['transcription']}.collect do |assignment|
    chunk = Audibleturk::Transcription::Chunk.new(assignment['transcription'])
    chunk.url = assignment['url']
    chunk.project = assignment['project_id']
    chunk.worker = assignment['worker']
    chunk.hit = assignment['hit_id']
  end
  transcription = Audibleturk::Transcription.new(project.name, transcription_chunks)
  transcription.subtitle = project.local.subtitle
  File.delete("#{project.local.path}/#{filename[:working]}") if File.exists?("#{project.local.path}/#{filename[:working]}")
  done = (transcription.to_a.length == project.local.audio_chunks.length)
  out_file = done ? filename[:done] : filename[:working]
  template ||= IO.read("#{project.config.app}/templates/transcript.html.erb")
  File.open("#{project.local.path}/#{out_file}", 'w') do |out|
    out << ERB.new(template, nil, '<>').result(binding())
  end
  $stderr.puts "Wrote #{out_file} to local folder #{project.name}."
  if not(project.local.amazon_hit_type_id)
    amazon_hit_type_id = need[key].first.hit.type_id
    if need[key].select{|result| result.hit.type_id == amazon_hit_type_id}.size == need[key].size
      project.local.amazon_hit_type_id = amazon_hit_type_id
    end
  end
end

