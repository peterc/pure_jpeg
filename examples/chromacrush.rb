#!/usr/bin/env ruby
require_relative "../lib/pure_jpeg"

# Chroma crush: high luminance quality with aggressively compressed chrominance.
# Detail and edges stay sharp but color collapses into large blocky patches
# with hue shifts.

if ARGV.length < 1
  $stderr.puts "Usage: #{$0} INPUT.(jpg|png) [OUTPUT.jpg] [luma_quality] [chroma_quality]"
  exit 1
end

input = ARGV[0]
output = ARGV[1] || input.sub(/(\.\w+)$/, '_chromacrush.jpg')
luma_quality = (ARGV[2] || 90).to_i
chroma_quality = (ARGV[3] || 5).to_i

if input.downcase.end_with?(".png")
  require "chunky_png"
  source = PureJPEG::Source::ChunkyPNGSource.new(ChunkyPNG::Image.from_file(input))
else
  source = PureJPEG.read(input)
end

PureJPEG.encode(source, quality: luma_quality, chroma_quality: chroma_quality).write(output)
puts "#{input} -> #{output} (#{File.size(output)} bytes, luma q#{luma_quality}, chroma q#{chroma_quality})"
