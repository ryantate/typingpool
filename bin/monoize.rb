#!/usr/bin/env ruby

require 'pp'

usage = "monoize.rb AUDIOFILE\n"
file = ARGV[0] or abort usage
bitrate = `ffmpeg -i '#{file}' 2>&1`.scan(/(\d+) kb\/s/)[1][0]
bitrate ||= 192
name = File.dirname(file)
name += '/' if name
name += File.basename(file, '.*') + '.mono' + File.extname(file)
puts `ffmpeg -i '#{file}' -ac 1 -ab #{bitrate}k '#{name}'`
