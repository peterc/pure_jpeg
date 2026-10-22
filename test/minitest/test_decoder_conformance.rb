# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "json"

class TestDecoderConformance < Minitest::Test
  include TestHelper

  def test_external_images_match_libjpeg_pixels
    manifest = JSON.parse(File.read(fixture_path("decoder/manifest.json")))
    manifest.each do |name, expected|
      path = fixture_path("decoder/#{name}.jpg")
      unless expected["supported"]
        assert_raises(PureJPEG::DecodeError, name) { PureJPEG.read(path) }
        next
      end
      image = PureJPEG.read(path)
      assert_equal [expected["width"], expected["height"]], [image.width, image.height], name
      rgb = "".b
      image.each_rgb { |_x, _y, r, g, b| rgb << r << g << b }
      assert_equal expected["rgb_sha256"], Digest::SHA256.hexdigest(rgb), name
    end
  end

  def test_marker_fill_preserves_progressive_pixels
    data = File.binread(fixture_path("decoder/restart-444.jpg"))
    padded = data.gsub("\xff\xc4".b, "\xff\xff\xc4".b)
    assert_equal PureJPEG.read(data).packed_pixels, PureJPEG.read(padded).packed_pixels
  end

  def test_late_quantization_table_does_not_change_existing_components
    data = File.binread(fixture_path("decoder/restart-444.jpg"))
    dqt = "\xff\xdb\x00\x43\x00".b + "\xff".b * 64
    changed = data[0...-2] + dqt + data[-2..]
    assert_equal PureJPEG.read(data).packed_pixels, PureJPEG.read(changed).packed_pixels
  end
end
