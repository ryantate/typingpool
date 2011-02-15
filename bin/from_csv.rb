#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'
require 'optparse'

home = "#{ENV['HOME']}/Applications/audibleturk"

csv_file = ARGV[0] or abort "Usage: from_csv.rb CSV_FILE [AUDIO_URL_PATH]\n"
audio_url_path = ARGV[1]
template = IO.read("#{home}/transcription.html.erb")

transcription = Audibleturk::Transcription.from_csv(IO.read(csv_file))

if (audio_url_path)
  audio_url_path = audio_url_path.sub(/\/\s*$/, '')
  transcription.each { |chunk| chunk.url = "#{audio_url_path}/#{chunk.filename}" }
end

html = ERB.new(template, nil, '<>').result

  print html

