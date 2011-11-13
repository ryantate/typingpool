#!/usr/bin/env ruby

require 'optparse'
require 'audibleturk'

options = {
  :files => [],
  :voices => [],
  :unusual => [],
  :chunk => '1:00'
}
OptionParser.new do |opts|
  options[:banner] = opts.banner = "USAGE: tp-make --file foo.mp3 [--file bar.mp3...] --title Foo --chunks 1:00 [--subtitle 'Foo telephone interview about Yahoo Hack Day'][--voice 'John Foo' --voice 'Sally Bar, Female interiewer with British accent'][--unusual 'Yahoo' --unusual 'Hack Day' --unusual 'Sunnyvale, Chad Dickerson, Zawodny'][--moveorig]\n"

  opts.on('--file FILE', 'Audio file to be transcribed. Required. May be specified repeatedly for multiple files. FILES WILL BE SORTED naively, so order is unimportant.') do |file|
    options[:files].push(file)
  end

  opts.on('--title TITLE', 'Title for naming files and the transcript. Required.') do |title|
    options[:title] = title
  end

  opts.on('--subtitle SUBTITLE', 'Subtitle for the transcript. Optional.') do |subtitle|
    options[:subtitle] = subtitle
  end

  opts.on('--chunks MM:SS' 'Audio will be divided into chunks for transcribing, each this many minutes and seconds long. Optional. Default is 1:00.  Format can be MM:SS, SS, or HH:MM:SS, plus optional decimal values (MM:SS.ss etc.)') do |chunk|
    options[:chunk] = chunk
  end

  opts.on('--voice "NAME[, TITLE]"', 'Name and optional title of a person in the transcript. Optional. May be specified repeatedly for multiple voices.') do |voice|
    options[:voices].push(voice)
  end

  opts.on('--unusual WORD[,WORD, WORD,...]', 'An unusual word occuring in the transcript, to help the transcriber. Optional. May be specified repeatedly for multiple words. May accept multiple arguments with commas.') do |word|
    options[:unusual].push(word)
  end

  opts.on('--config PATH', 'Alternate config file to use. Optional. Default is ~/.audibleturk') do |config|
    options[:config] = config
  end

  opts.on('--bitrate KBPS', 'Bitrate for output files, expressed as an integer representing kilobits per second. Optional. Default is to match the bitrate of the input files.') do |kbps|
    options[:bitrate] = kbps
  end

  opts.on('--moveorig', 'Move the original files into instead of copying them.') do
    options[:moveorig] = true
  end

  opts.on('--help', 'Display this screen') do
    puts opts
    exit
  end
end.parse!

abort "No files specified" if options[:files].empty?
options[:files].sort!
options[:files].each do |file|
  File.extname(file) or abort "You need a file extension on the file '#{file}'"
  File.exist?(file) or abort "There is no file '#{file}'"
end

config = Audibleturk::Config.file(options[:config])
%w(scp url app).each do |param|
  abort "Required param '#{param}' missing from config file '#{config.path}'" if config.param[param].to_s.empty?
end

options[:unusual].collect!{|unusual| unusual.split(/\s*,\s*/)}.flatten!
options[:voices].collect! do |voice| 
  name, description = voice.split(/\s*,\s*/)
  {
    :name => name,
    :description => (description || '')
  }
end

project = Audibleturk::Project.new(options[:title], config)
begin
  project.interval = options[:chunk] if options[:chunk]
rescue Audibleturk::Error::Argument::Format
  abort "Could not make sense of chunk argument '#{options[:chunk]}'. Required format is SS, or MM:SS, or HH:MM:SS, with optional decimal values (e.g. MM:SS.ss)"
end
begin
  project.bitrate = options[:bitrate] if options[:bitrate]
rescue Audibleturk::Error::Argument::Format
  abort "Could not make sense of bitrate argument '#{options[:bitrate]}'. Should be an integer corresponding to kb/s."
end

begin
  project.create_local
rescue Errno::EEXIST
  abort "The name #{options[:title]} is taken"
end
project.local.subtitle = options[:subtitle] if options[:subtitle]
project.local.add_audio(options[:files], options[:moveorig])

files = project.convert_audio{|file, kbps| puts "Converting #{File.basename(file)} to mp3"}

puts "Merging audio" if files.length > 1
file = project.merge_audio(files)

puts "Splitting audio into uniform bits"
files = project.split_audio(file)

remote_files = project.upload_audio(files) do |file, as, www|
  puts "Uploading #{File.basename(file)} to #{www.host}/#{www.path} as #{as}"
end

assignment_path = project.create_assignment_csv(remote_files, options[:unusual], options[:voices])
puts "Wrote #{assignment_path}"

puts "Opening project folder #{project.local.path}"
project.local.finder_open

puts "Deleting temp files"
project.local.rm_tmp_dir

puts "Done"
