#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

home = "#{Dir.home}/Documents/Software/dist/ruby/audibleturk"

puts "Collecting results from Amazon..."
results = Audibleturk::Remote::Result.all_approved

puts "Sorting results..."
available_folders = results.collect{|result| result.transcription.title }.uniq.select{|title| Audibleturk::Folder.named(title)}

template = IO.read("#{home}/www/transcription.html.erb") unless available_folders.empty?

available_folders.each do |folder|
  shortname = folder
  folder = Audibleturk::Folder.named(folder)
  filename = {
    'done' => 'transcript.html',
    'working' => 'transcript_in_progress.html'
  }
  next if File.exists?("#{folder.path}/#{filename['done']}")
  transcription = Audibleturk::Transcription.new(shortname, results.select{|result| result.transcription.title == shortname}.collect{|result| result.transcription})
  transcription.each{|chunk| chunk.url = "audio/#{chunk.filename_local}" }
  transcription.subtitle = folder.subtitle
  html = ERB.new(template, nil, '<>').result(binding())
  File.delete("#{folder.path}/#{filename['working']}") if File.exists?("#{folder.path}/#{filename['working']}")
  is_done = (transcription.to_a.length == folder.audio_chunks)
  out_file = is_done ? filename['done'] : filename['working']
  out_paths = ["#{folder.path}/#{out_file}"]
  out_paths.push("#{folder.path}/originals/#{out_file}") if is_done
  out_paths.each do |path|
    File.open(path, 'w') do |out|
      out << html
    end
  end
  puts "Wrote #{out_file} to folder #{shortname}."
end

