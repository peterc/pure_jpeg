# frozen_string_literal: true

require "pure_jpeg"

source = PureJPEG::Source::RawSource.new(19, 13) { |_x, _y| [64, 128, 192] }
[false, true].each do |grayscale|
  data = PureJPEG.encode(source, quality: 85, grayscale: grayscale).to_bytes
  info = PureJPEG.info(data)
  raise "Wrong dimensions" unless info.width == 19 && info.height == 13
  raise "Wrong component count" unless info.component_count == (grayscale ? 1 : 3)
  raise "Unexpected progressive frame" if info.progressive
  raise "Unexpected ICC profile" unless info.icc_profile.nil?

  # Metadata must also work without the compressed scan data.
  sos = data.index("\xFF\xDA".b)
  raise "Missing SOS" unless sos
  header_info = PureJPEG.info(data[0...(sos + 2)])
  raise "Wrong header dimensions" unless header_info.width == 19 && header_info.height == 13
  puts "metadata grayscale=#{grayscale}: #{info.width}x#{info.height}, #{info.component_count} components"
end

info = PureJPEG.info(File.expand_path("fixtures/a-progressive.jpg", __dir__))
raise "Wrong progressive dimensions" unless info.width == 1024 && info.height == 1024
raise "Wrong progressive component count" unless info.component_count == 3
raise "Missing progressive flag" unless info.progressive
puts "progressive metadata: #{info.width}x#{info.height}"
