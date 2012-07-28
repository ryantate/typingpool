#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'

lines_each = 2
if ARGV.last.to_s.match(/^\d+$/)
  lines_each = ARGV.pop.to_i
end

if ARGV.empty?
  abort "USAGE: #{File.basename($PROGRAM_NAME)} PROJECT_DIR [PROJECT_DIR...] [LINES_EACH=2]"
end

data_files = ARGV.map do |path| 
  data_file = nil
  expanded = File.expand_path(path)
  if not(File.exists? expanded)
    abort "No such dir #{path}"
  end
  if not(File.directory? expanded)
    abort "Not a dir: #{path}"
  end
  %w(data csv).each do |data_dir_name|
    possible_data_file = File.join(expanded, data_dir_name, 'assignment.csv')
    if File.exists? possible_data_file
      data_file = possible_data_file
    end
  end #%w().each do...
  if not(data_file)
    abort "Dir #{path} has no data/assignment.csv or csv/assignment.csv"
  end
  data_file
end #ARGV.map

assignments=[]
data_files.each do |path|
  csv = Typingpool::Filer::CSV.new(path)
  with_transcripts = csv.reject{|assignment| assignment['transcript'].to_s.empty? }
  next if with_transcripts.empty?
  seeking = with_transcripts.count
  if seeking > lines_each
    seeking = lines_each
  end
  assignments.push(*with_transcripts.sample(seeking))
end #data_files.each do...

if assignments.empty?
  abort "No transcripts found"
end
fixtures_dir = File.join(Typingpool::Utility.lib_dir, 'test', 'fixtures')
Typingpool::Filer::CSV.new(File.join(fixtures_dir, 'transcript-chunks.csv')).write(assignments)
