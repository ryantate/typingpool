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
  options[:banner] = opts.banner = "USAGE: #{File.basename($PROGRAM_NAME)} --title Foo --file foo.mp3 [--file bar.mp3...] [--chunks 1:00] [--subtitle 'Hack Day interview'][--voice 'John' --voice 'Pat Foo, British female'...][--unusual 'Hack Day' --unusual 'Sunnyvale, Chad Dickerson'...][--bitrate 256][--moveorig]\n"

  opts.on('--file FILE', 'Required. Audio for transcribing. Repeatable (sorting is by name).') do |file|
    options[:files].push(file)
  end

  opts.on('--title TITLE', 'Required. For file names and transcript.') do |title|
    options[:title] = title
  end

  opts.on('--subtitle SUBTITLE', 'For transcript.') do |subtitle|
    options[:subtitle] = subtitle
  end

  opts.on('--chunks MM:SS', 'Default: 1:00. Audio divided thusly for transcribing. Try also HH:MM:SS.ss and SSS.') do |chunk|
    options[:chunk] = chunk
  end

  opts.on('--voice "NAME[, DESCR]"', 'Name and optional description of person in recording, to aid transcriber. Repeatable.') do |voice|
    options[:voices].push(voice)
  end

  opts.on('--unusual WORD[,WORD,...]', 'Unusual word occuring in the transcript, to aid the transcriber. Repeatable, or use commas.') do |word|
    options[:unusual].push(word)
  end

  opts.on('--config PATH', 'Default: ~/.audibleturk. A config file.') do |config|
    options[:config] = config
  end

  opts.on('--bitrate KBPS', 'Default: Mirror input. Output bitrate in kb/s.') do |kbps|
    options[:bitrate] = kbps
  end

  opts.on('--moveorig', 'Move input files instead of copying.') do
    options[:moveorig] = true
  end

  opts.on('--help', 'Display this screen.') do
    puts opts
    exit
  end
end.parse!

abort "No files specified.\n\n#{options[:banner]}\n\n--help for more" if options[:files].empty?
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
