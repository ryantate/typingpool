#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
url_at_form_field = ARGV[0] || 'audibleturk_url'

puts "Collecting results from Amazon..."
results = Audibleturk::Amazon::Result.all_approved(:url_at => url_at_form_field)
needed_titles = results.collect{|result| result.transcription.title }.uniq.select{|title| Audibleturk::Project.new(title).folder}

template = nil
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}
needed_titles.each do |title|
  project = Audibleturk::Project.new(title)
  next if File.exists?("#{project.folder.path}/#{filename[:done]}")
  transcription = Audibleturk::Transcription.new(title, results.select{|result| result.transcription.title == title}.collect{|result| result.transcription})
  www_files = transcription.collect{|chunk| chunk.filename }
  transcription.each{|chunk| chunk.url = "audio/#{chunk.filename_local}" }
  transcription.subtitle = project.folder.subtitle
  File.delete("#{project.folder.path}/#{filename[:working]}") if File.exists?("#{project.folder.path}/#{filename[:working]}")
  done = (transcription.to_a.length == project.folder.audio_chunks)
  out_file = done ? filename[:done] : filename[:working]
  template ||= IO.read("#{File.expand_path(Audibleturk::Config.param['app'])}/www/transcript.html.erb")
  html = ERB.new(template, nil, '<>').result(binding())
  File.open("#{project.folder.path}/#{out_file}", 'w') do |out|
    out << html
  end
  puts "Wrote #{out_file} to folder #{title}."
  if done && project.config.param['scp']
    removed = project.www.remove(www_files)
    if removed[:success]
      puts "Removed #{project.name} files from #{project.www.host}"
    else
      puts "Could not remove #{project.name} files from #{project.www.host}: #{removed[:message]}"
    end
  end
end
