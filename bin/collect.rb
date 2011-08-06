#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

#Name of form field in Mechanical Turk assignment form
# containing URL to audio file
url_at_form_field = ARGV[0] || 'audibleturk_url'

puts "Collecting results from Amazon..."
results = Audibleturk::Amazon::Result.all_approved(:url_at => url_at_form_field)
needed_titles = results.collect{|result| result.transcription.title }.uniq.select{|title| Audibleturk::Folder.named(title)}

template = nil
filename = {
  :done => 'transcript.html',
  :working => 'transcript_in_progress.html'
}
needed_titles.each do |title|
  folder = Audibleturk::Folder.named(title)
  next if File.exists?("#{folder.path}/#{filename[:done]}")
  transcription = Audibleturk::Transcription.new(title, results.select{|result| result.transcription.title == title}.collect{|result| result.transcription})
  transcription.each{|chunk| chunk.url = "audio/#{chunk.filename_local}" }
  transcription.subtitle = folder.subtitle
  File.delete("#{folder.path}/#{filename[:working]}") if File.exists?("#{folder.path}/#{filename[:working]}")
  out_file = (transcription.to_a.length == folder.audio_chunks) ? filename[:done] : filename[:working]
  template ||= IO.read("#{File.expand_path(Audibleturk::Config.param['app'])}/www/transcript.html.erb")
  html = ERB.new(template, nil, '<>').result(binding())
  File.open("#{folder.path}/#{out_file}", 'w') do |out|
    out << html
  end
  puts "Wrote #{out_file} to folder #{title}."
end
