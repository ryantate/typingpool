#!/usr/bin/env ruby

require 'csv'
require 'fileutils'
require 'pp'

path = ARGV[0] or abort "No CSV file path supplied"
path.sub(/\/$/, '')
file = IO.read(path) or abort "Could not find CSV file at #{path}"
rows = []
CSV.parse(file) do |row|
  next if /^HITId/.match(row[0])
  filename, basename, sequence, extension = /.+\/((\w+)-(\d+)(\.[^\/]+))$/.match(row[25]).captures
  filename or raise "Unexpected format to url #{row[25]}"
  offset_start = (sequence.to_i - 1) * 5
  offset_end = offset_start + 5
  new_filename = "#{basename}.#{offset_start}.00-#{offset_end}.00#{extension}"
  row[25] = "audio/#{new_filename}"
  row[26] = row[26].gsub(/\r\n/, "\n")
  row[26] = row[26].gsub(/\r/, "\n")
  rows.push(row)
dir = File.dirname(path)
  FileUtils.cp("#{dir}/../audio/#{filename}", "#{dir}/../audio/#{new_filename}")
end


print(CSV.generate do |csv|
  rows.each do |row|
    csv << row
  end
end)


