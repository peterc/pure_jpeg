# frozen_string_literal: true

#!/usr/bin/env ruby
require "chunky_png"
require_relative "../lib/pure_jpeg"

args = ARGV.dup
grayscale = args.delete("--grayscale") || args.delete("-g")

if args.length < 2
  $stderr.puts "Usage: #{$0} [--grayscale] INPUT.png OUTPUT.jpg [quality]"
  exit 1
end

input, output = args[0], args[1]
quality = (args[2] || 85).to_i

image = ChunkyPNG::Image.from_file(input)
mode = grayscale ? "grayscale" : "color"
PureJPEG.from_chunky_png(image, quality: quality, grayscale: !!grayscale).write(output)

puts "#{input} (#{image.width}x#{image.height}) -> #{output} (#{File.size(output)} bytes, q#{quality}, #{mode})"
