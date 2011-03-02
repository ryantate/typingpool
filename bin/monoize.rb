#!/usr/bin/env ruby

require 'pp'

usage = "monoize.rb AUDIOFILE\n"
file = ARGV[0] or abort usage
bitrate = `/usr/local/bin/ffmpeg -i '#{file}' 2>&1`
bitrate = bitrate.scan(/(\d+) kb\/s/)
bitrate = bitrate.empty? ? nil : bitrate[1][0]
bitrate ||= 192
name = File.dirname(file)
name += '/' if name
name += File.basename(file, '.*') + '.mono' + File.extname(file)
puts `/usr/local/bin/ffmpeg -i '#{file}' -ac 1 -ab #{bitrate}k '#{name}'`
