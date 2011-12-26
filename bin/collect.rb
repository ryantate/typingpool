#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'
require 'optparse'

options = {
  :url_at => 'typingpool_url',
  :id_at => 'typingpool_project_id'
}

OptionParser.new do |commands|
  options[:banner] = commands.banner = "USAGE: #{File.basename($PROGRAM_NAME)} [--url_at=#{options[:url_at]}] [--id_at=#{options[:id_at]}] [--sandbox]\n"
  commands.on('--sandbox', "Collect from the Mechanical Turk test sandbox") do
    options[:sandbox] = true
  end
  commands.on('--url_at=PARAM', "Name of the HTML form field for audio URLs.", " Default is #{options[:url_at]}") do |url_at|
    options[:url_at] = url_at
  end
  commands.on('--id_at=PARAM', "Name of the HTML form field for project IDs.", " Default is #{options[:id_at]}") do |id_at|
    options[:id_at] = id_at
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

$stderr.puts "Collecting results from Amazon..."
Audibleturk::Amazon.setup(:sandbox => options[:sandbox])
results = Audibleturk::Amazon::Result.all_approved(:url_at => options[:url_at], :id_at => options[:id_at])
#Only pay attention to results that have a local folder waiting to receive them:
projects = {}
need = {}
$stderr.puts "Looking for local project folders to receive results..."
results.each do |result| 
  key = result.transcription.project.to_s + result.transcription.title.to_s
  if need[key] == false
    next
  elsif need[key]
    need[key].push(result)
  else
    need[key] = false
    project = Audibleturk::Project.new(result.transcription.title)
    #folder must exist
    local = project.local or next;
    #transcript must not be complete
    next if File.exists?("#{local.path}/#{filename[:done]}")
    #folder id must match incoming id
    next if local.id && (local.id != result.transcription.project)
    projects[key] = project
    need[key] = [result]
  end
end
template = nil
projects.each do |key, project|
  transcription = Audibleturk::Transcription.new(project.name, need[key].collect{|result| result.transcription})
  transcription.subtitle = project.local.subtitle
  File.delete("#{project.local.path}/#{filename[:working]}") if File.exists?("#{project.local.path}/#{filename[:working]}")
  done = (transcription.to_a.length == project.local.audio_chunks.length)
  out_file = done ? filename[:done] : filename[:working]
  template ||= IO.read("#{project.config.app}/templates/transcript.html.erb")
  File.open("#{project.local.path}/#{out_file}", 'w') do |out|
    out << ERB.new(template, nil, '<>').result(binding())
  end
  $stderr.puts "Wrote #{out_file} to local folder #{project.name}."
  if done && project.config.param['scp']
    begin
      removed = project.www.remove(transcription.collect{|chunk| chunk.filename })
    rescue Audibleturk::Error::SFTP => e
      $stderr.puts "Could not remove #{project.name} files from #{project.www.host}: #{e}"
    else
      $stderr.puts "Removed #{project.name} files from #{project.www.host}"
    end
  end
end
