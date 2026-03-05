#!/usr/bin/env ruby
require_relative "../lib/pure_jpeg"

if ARGV.length < 1
  $stderr.puts "Usage: #{$0} INPUT.jpg [OUTPUT.jpg] [quality]"
  exit 1
end

input = ARGV[0]
output = ARGV[1] || input.sub(/(\.\w+)$/, '_kodak\1')
quality = (ARGV[2] || 20).to_i

image = PureJPEG.read(input)
PureJPEG.encode(image, quality: quality, scramble_quantization: true).write(output)

puts "#{input} -> #{output} (#{File.size(output)} bytes, q#{quality}, scrambled quantization)"
