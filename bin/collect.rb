#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
url_at_form_field = ARGV[0] || 'audibleturk_url'

puts "Collecting results from Amazon..."
results = Audibleturk::Amazon::Result.all_approved(:url_at => url_at_form_field)
#Only pay attention to results that have a local folder waiting to receive them:
needed_titles = results.collect{|result| result.transcription.title }.uniq.select{|title| Audibleturk::Project.new(title).local}

template = nil
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}
needed_titles.each do |title|
  project = Audibleturk::Project.new(title)
  next if File.exists?("#{project.local.path}/#{filename[:done]}")
  transcription = Audibleturk::Transcription.new(title, results.select{|result| result.transcription.title == title}.collect{|result| result.transcription})
  transcription.subtitle = project.local.subtitle
  File.delete("#{project.local.path}/#{filename[:working]}") if File.exists?("#{project.local.path}/#{filename[:working]}")
  done = (transcription.to_a.length == project.local.audio_chunks)
  out_file = done ? filename[:done] : filename[:working]
  template ||= IO.read("#{project.config.app}/www/transcript.html.erb")
  File.open("#{project.local.path}/#{out_file}", 'w') do |out|
    out << ERB.new(template, nil, '<>').result(binding())
  end
  puts "Wrote #{out_file} to local folder #{title}."
  if done && project.config.param['scp']
    removed = project.www.remove(transcription.collect{|chunk| chunk.filename })
    if removed[:success]
      puts "Removed #{project.name} files from #{project.www.host}"
    else
      puts "Could not remove #{project.name} files from #{project.www.host}: #{removed[:message]}"
    end
  end
end
