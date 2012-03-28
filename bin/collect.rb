#!/usr/bin/env ruby

require 'erb'
require 'typingpool'
require 'optparse'

options = {
  :config => Typingpool::Config.file
}

OptionParser.new do |commands|
  options[:banner] = commands.banner = "USAGE: #{File.basename($PROGRAM_NAME)} [--config PATH] [--sandbox]\n"
  commands.on('--sandbox', "Collect from the Mechanical Turk test sandbox") do
    options[:sandbox] = true
  end
  commands.on('--config=PATH', "Default: ~/.typingpool", " A config file") do |config|
    path = File.expand_path(config)
    File.exists?(path) && File.file?(path) or abort "No such file #{path}"
    options[:config] = Typingpool::Config.file(config)
  end
  commands.on('--fixture=PATH', "Optional. For testing purposes only.", "  A VCR ficture for running with mock data.") do |fixture|
    options[:fixture] = fixture
  end
  commands.on('--help', "Display this screen") do
    STDERR.puts commands
    exit
  end
end.parse!

if options[:fixture]
  require 'vcr'
  VCR.configure do |c|
    c.cassette_library_dir = File.dirname(options[:fixture])
    c.hook_into :webmock 
    c.filter_sensitive_data('<AWS_KEY>'){ options[:config].amazon.key }
    c.filter_sensitive_data('<AWS_SECRET>'){ options[:config].amazon.secret }
  end
  VCR.insert_cassette(File.basename(options[:fixture], '.*'), :record => :new_episodes)
end

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}

STDERR.puts "Collecting results from Amazon"
Typingpool::Amazon.setup(:sandbox => options[:sandbox], :config => options[:config])
results = Typingpool::Amazon::Result.all_approved
#Only pay attention to results that have a local folder waiting to receive them:
projects = {}
need = {}
STDERR.puts "Looking for local project folders to receive results" unless results.empty?
results.each do |result| 
  key = result.project_id
  if need[key]
    need[key].push(result)
  elsif need[key] == false
    next
  else
    need[key] = false
    project = Typingpool::Project.new(result.project_title_from_url, options[:config])
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
  results_by_url = Hash[ *need[key].map{|result| [result.url, result] }.flatten ]
  project.local.csv('data', 'assignment.csv').each! do |assignment|
    result = results_by_url[assignment['audio_url']] or next
    next if assignment['transcription']
    assignment['transcription'] = result.transcription.body
    assignment['worker'] = result.transcription.worker
    assignment['hit_id'] = result.hit_id
  end
  transcription_chunks = project.local.csv('data', 'assignment.csv').select{|assignment| assignment['transcription']}.map do |assignment|
    chunk = Typingpool::Transcription::Chunk.new(assignment['transcription'])
    chunk.url = assignment['audio_url']
    chunk.project = assignment['project_id']
    chunk.worker = assignment['worker']
    chunk.hit = assignment['hit_id']
    chunk
  end
  transcription = Typingpool::Transcription.new(project.name, transcription_chunks)
  transcription.subtitle = project.local.subtitle
  File.delete(File.join(project.local.path, filename[:working])) if File.exists?(File.join(project.local.path, filename[:working]))
  done = (transcription.to_a.length == project.local.audio_chunks.length)
  out_file = done ? filename[:done] : filename[:working]
  begin
    template ||= Typingpool::Template.from_config('transcript', options[:config])
  rescue Typingpool::Error::File::NotExists => e
    abort "Couldn't find the template dir in your config file: #{e}"
  rescue Typingpool::Error => e
    abort "There was a fatal error with the transcript template: #{e}"
  end
  File.open(File.join(project.local.path, out_file), 'w') do |out|
    out << template.render({:transcription => transcription})
  end
  STDERR.puts "Wrote #{out_file} to local folder #{project.name}."
end

if options[:fixture]
  VCR.eject_cassette
end
