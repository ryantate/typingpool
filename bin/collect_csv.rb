#!/usr/bin/env ruby

require 'erb'
require 'audibleturk'

csv_file = ARGV[0] or abort "Usage: collect_csv.rb CSV_FILE [AUDIO_URL_PATH [REMOVE_FILENAME_RANDOMIZATION=1]]\n"
audio_url_path = ARGV[1] ? ARGV[1].dup : nil
remove_filename_randomization = ARGV[2] || true
remove_filename_randomization = false if remove_filename_randomization.to_s == '0'
template = IO.read("#{Audibleturk::Config.app}/templates/transcript.html.erb")

transcription = Audibleturk::Transcription.from_csv(IO.read(csv_file))

if (audio_url_path)
  audio_url_path.sub!(/\/\s*$/, '')
  transcription.each do |chunk| 
    filename = remove_filename_randomization ? chunk.filename_local : chunk.filename
    chunk.url = "#{audio_url_path}/#{filename}" 
  end
  transcription.url = "#{audio_url_path}/#{transcription.title}.all.mp3" if (remove_filename_randomization && transcription.title)
end

html = ERB.new(template, nil, '<>').result
print html

