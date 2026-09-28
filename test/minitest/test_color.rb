# frozen_string_literal: true

require_relative "test_helper"

class TestColor < Minitest::Test
  include TestHelper

  def test_color_encoding
    source = gradient_source(128, 128)
    data = PureJPEG.encode(source, quality: 85).to_bytes

    assert data.start_with?("\xFF\xD8".b)
    assert data.bytesize > 0
  end

  def test_grayscale_encoding
    source = gradient_source(128, 128)
    data = PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes

    assert data.start_with?("\xFF\xD8".b)
    assert data.bytesize > 0
  end

  def test_grayscale_smaller_than_color
    source = gradient_source(128, 128)
    color = PureJPEG.encode(source, quality: 85).to_bytes
    gray = PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes

    assert gray.bytesize < color.bytesize, "Grayscale should be smaller than color"
  end

  def test_grayscale_round_trip_has_equal_channels
    source = gradient_source(64, 64)
    data = PureJPEG.encode(source, quality: 95, grayscale: true).to_bytes
    image = PureJPEG.read(data)
    pixel = image[32, 32]

    assert_equal pixel.r, pixel.g
    assert_equal pixel.g, pixel.b
  end
end
