# frozen_string_literal: true

#!/usr/bin/env ruby
require "chunky_png"
require_relative "../lib/pure_jpeg"

if ARGV.length < 2
  $stderr.puts "Usage: #{$0} INPUT.jpg OUTPUT.png"
  exit 1
end

input, output = ARGV[0], ARGV[1]

image = PureJPEG.read(input)

png = ChunkyPNG::Image.new(image.width, image.height)
image.each_pixel do |x, y, pixel|
  png[x, y] = ChunkyPNG::Color.rgb(pixel.r, pixel.g, pixel.b)
end
png.save(output)

puts "#{input} (#{image.width}x#{image.height}) -> #{output} (#{File.size(output)} bytes)"
