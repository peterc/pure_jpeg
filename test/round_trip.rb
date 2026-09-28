# frozen_string_literal: true

require "pure_jpeg"

# Odd dimensions exercise padding at the edges of JPEG blocks.
source = PureJPEG::Source::RawSource.new(19, 13) do |x, y|
  [x * 12, y * 18, 96]
end

[false, true].each do |grayscale|
  data = PureJPEG.encode(source, quality: 90, grayscale: grayscale).to_bytes
  raise "Missing SOI" unless data.start_with?("\xFF\xD8".b)
  raise "Missing EOI" unless data.end_with?("\xFF\xD9".b)

  image = PureJPEG.read(data)
  raise "Wrong dimensions" unless image.width == 19 && image.height == 13
  raise "Wrong pixel count" unless image.packed_pixels.length == 19 * 13

  pixel = image[9, 6]
  if grayscale
    raise "Grayscale channels differ" unless pixel.r == pixel.g && pixel.g == pixel.b
  else
    raise "Red channel differs too much" unless (pixel.r - 108).abs <= 15
    raise "Green channel differs too much" unless (pixel.g - 108).abs <= 15
    raise "Blue channel differs too much" unless (pixel.b - 96).abs <= 15
  end

  # spin test compares these with CRuby, checking every byte and pixel.
  puts "grayscale=#{grayscale}"
  puts data.bytes.join(",")
  puts image.packed_pixels.join(",")
end
