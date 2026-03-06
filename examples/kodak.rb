#!/usr/bin/env ruby
require_relative "../lib/pure_jpeg"

if ARGV.length < 1
  $stderr.puts "Usage: #{$0} INPUT.(jpg|png) [OUTPUT.jpg] [quality]"
  exit 1
end

input = ARGV[0]
output = ARGV[1] || input.sub(/(\.\w+)$/, '_kodak.jpg')
quality = (ARGV[2] || 20).to_i

if input.downcase.end_with?(".png")
  require "chunky_png"
  source = PureJPEG::Source::ChunkyPNGSource.new(ChunkyPNG::Image.from_file(input))
else
  source = PureJPEG.read(input)
end

PureJPEG.encode(source, quality: quality, scramble_quantization: true).write(output)

puts "#{input} -> #{output} (#{File.size(output)} bytes, q#{quality}, scrambled quantization)"
