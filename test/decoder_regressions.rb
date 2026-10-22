# frozen_string_literal: true

require "pure_jpeg"

# External JPEGs exercise progressive scans, restarts, separate baseline
# component scans, mixed scans, and unusual sampling factors. Spin compares
# every decoded pixel with a fresh CRuby run.
names = [
  "edge-420", "restart-420", "edge-422", "restart-422",
  "edge-444", "restart-444", "edge-440", "restart-440",
  "edge-411", "restart-411", "edge-gray", "restart-gray", "tiny",
  "baseline-restart", "luma-subsampled", "sequential-multiscan",
  "sequential-edge-restart", "mixed-scan-restart"
]
names.each do |name|
  image = PureJPEG.read(File.expand_path("fixtures/decoder/#{name}.jpg", __dir__))
  raise "Wrong pixel count" unless image.packed_pixels.length == image.width * image.height
  puts "#{name}: #{image.width}x#{image.height}"
  puts image.packed_pixels.join(",")
end

data = File.binread(File.expand_path("fixtures/decoder/restart-444.jpg", __dir__))
expected = PureJPEG.read(data).packed_pixels
padded = data.gsub("\xFF\xC4".b, "\xFF\xFF\xC4".b)
raise "Marker fill changed pixels" unless PureJPEG.read(padded).packed_pixels == expected

dqt = "\xFF\xDB\x00\x43\x00".b + "\xFF".b * 64
changed = data[0...-2] + dqt + data[-2..]
raise "Late quantization table changed pixels" unless PureJPEG.read(changed).packed_pixels == expected
puts "marker fill and late quantization table: unchanged"

begin
  PureJPEG.read(File.expand_path("fixtures/decoder/rgb.jpg", __dir__))
  raise "Accepted unsupported RGB JPEG"
rescue PureJPEG::DecodeError => error
  puts "RGB JPEG: #{error.message}"
end
