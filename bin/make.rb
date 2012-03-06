#!/usr/bin/env ruby

require 'optparse'
require 'typingpool'

options = {
  :config => Typingpool::Config.file,
  :files => [],
  :voices => [],
  :unusual => [],
  :chunk => '1:00'
}
OptionParser.new do |opts|
  options[:banner] = opts.banner = "USAGE: #{File.basename($PROGRAM_NAME)} --title Foo --file foo.mp3 [--file bar.mp3...]\n  [--chunks 1:00] [--subtitle 'Hack Day interview']\n  [--voice 'John' --voice 'Pat Foo, British female'...]\n  [--unusual 'Hack Day' --unusual 'Sunnyvale, Chad Dickerson'...]\n  [--bitrate 256][--moveorig] [--config PATH]\n"

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

  opts.on('--voice "NAME[, DESCR]"', 'Name, optional description of recorded person, to aid transcriber. Repeatable.') do |voice|
    options[:voices].push(voice)
  end

  opts.on('--unusual WORD[,WORD,]', 'Unusual word within recording, to aid transcriber. Commas for multiple. Repeatable.') do |word|
    options[:unusual].push(word)
  end

  opts.on('--config PATH', 'Default: ~/.audibleturk. A config file.') do |config|
    path = File.expand_path(config)
    File.exists?(path) && File.file?(path) or abort "No such file #{path}"
    options[:config] = Typingpool::Config.file(config)
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
options[:banner] += "`#{File.basename($PROGRAM_NAME)} --help` for more information.\n"
abort "Unfamiliar argument '#{ARGV[0]}'" if ARGV.size > 0
abort "No files specified\n#{options[:banner]}" if options[:files].empty?
abort "No title specified\n#{options[:banner]}" if options[:title].to_s.empty?
options[:files].sort!
options[:files].each do |file|
  File.extname(file) or abort "You need a file extension on the file '#{file}'"
  File.exist?(file) or abort "There is no file '#{file}'"
end

config = options[:config]
%w(app).each do |param|
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

project = Typingpool::Project.new(options[:title], config)
begin
  project.interval = options[:chunk] if options[:chunk]
rescue Typingpool::Error::Argument::Format
  abort "Could not make sense of chunk argument '#{options[:chunk]}'. Required format is SS, or MM:SS, or HH:MM:SS, with optional decimal values (e.g. MM:SS.ss)"
end
begin
  project.bitrate = options[:bitrate] if options[:bitrate]
rescue Typingpool::Error::Argument::Format
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

remote_files = project.upload_audio(files) do |file, as, remote|
  puts "Uploading #{File.basename(file)} to #{remote.host}/#{remote.path} as #{as}"
end

assignment_path = project.create_assignment_csv(remote_files, options[:unusual], options[:voices])
puts "Wrote #{assignment_path}"

puts "Opening project folder #{project.local.path}"
project.local.finder_open if STDOUT.tty?

puts "Deleting temp files"
project.local.rm_tmp_dir

puts "Done"
