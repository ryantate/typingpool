#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
url_at_form_field = ARGV[0] || 'typingpool_url'
id_at_form_field = ARGV[1] || 'typingpool_project_id'
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}

puts "Collecting results from Amazon..."
results = Audibleturk::Amazon::Result.all_approved(:url_at => url_at_form_field, :id_at => id_at_form_field)
#Only pay attention to results that have a local folder waiting to receive them:
projects = {}
need = {}
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
  puts "Wrote #{out_file} to local folder #{project.name}."
  if done && project.config.param['scp']
    begin
      removed = project.www.remove(transcription.collect{|chunk| chunk.filename })
    rescue Audibleturk::Error::SFTP => e
      puts "Could not remove #{project.name} files from #{project.www.host}: #{e}"
    else
      puts "Removed #{project.name} files from #{project.www.host}"

    end
  end
end
