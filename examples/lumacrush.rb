#!/usr/bin/env ruby
require_relative "../lib/pure_jpeg"

# Luma crush: aggressively compress luminance while preserving chrominance.
# Produces a soft, oil-painting quality where detail is blocky but colors
# remain surprisingly accurate.

if ARGV.length < 1
  $stderr.puts "Usage: #{$0} INPUT.(jpg|png) [OUTPUT.jpg] [luma_quality] [chroma_quality]"
  exit 1
end

input = ARGV[0]
output = ARGV[1] || input.sub(/(\.\w+)$/, '_lumacrush.jpg')
luma_quality = (ARGV[2] || 10).to_i
chroma_quality = (ARGV[3] || 95).to_i

if input.downcase.end_with?(".png")
  require "chunky_png"
  source = PureJPEG::Source::ChunkyPNGSource.new(ChunkyPNG::Image.from_file(input))
else
  source = PureJPEG.read(input)
end

PureJPEG.encode(source, quality: luma_quality, chroma_quality: chroma_quality).write(output)
puts "#{input} -> #{output} (#{File.size(output)} bytes, luma q#{luma_quality}, chroma q#{chroma_quality})"
