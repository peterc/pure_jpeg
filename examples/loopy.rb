# frozen_string_literal: true

#!/usr/bin/env ruby
require_relative "../lib/pure_jpeg"

if ARGV.length < 1
  $stderr.puts "Usage: #{$0} INPUT.jpg [quality] [iterations]"
  exit 1
end

input = ARGV[0]
quality = (ARGV[1] || 60).to_i
iterations = (ARGV[2] || 5).to_i

basename = File.basename(input, File.extname(input))
dir = File.dirname(input)

image = PureJPEG.read(input)
puts "Source: #{input} (#{image.width}x#{image.height})"

iterations.times do |i|
  output = File.join(dir, "#{basename}_loop#{i + 1}.jpg")
  encoder = PureJPEG.encode(image, quality: quality)
  encoder.write(output)
  puts "  Pass #{i + 1}/#{iterations}: #{output} (#{File.size(output)} bytes)"
  image = PureJPEG.read(output)
end

puts "Done. #{iterations} re-encodes at q#{quality}."
