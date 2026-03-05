# frozen_string_literal: true

require_relative "test_helper"

class TestDecode < Minitest::Test
  include TestHelper

  def test_round_trip_color
    source = gradient_source(64, 64)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    assert_equal 64, image.width
    assert_equal 64, image.height
    assert_valid_pixel(image[0, 0])
    assert_valid_pixel(image[63, 63])
  end

  def test_round_trip_grayscale
    source = gradient_source(64, 64)
    data = PureJPEG.encode(source, quality: 95, grayscale: true).to_bytes
    image = PureJPEG.read(data)

    assert_equal 64, image.width
    assert_equal 64, image.height

    pixel = image[32, 32]
    assert_equal pixel.r, pixel.g
    assert_equal pixel.g, pixel.b
  end

  def test_decode_from_file
    source = gradient_source(64, 64)
    path = "/tmp/pure_jpeg_test_decode.jpg"
    PureJPEG.encode(source, quality: 85).write(path)

    image = PureJPEG.read(path)
    assert_equal 64, image.width
    assert_equal 64, image.height
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_re_encode_decoded_image
    source = gradient_source(64, 64)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    image = PureJPEG.read(data)

    re_encoded = PureJPEG.encode(image, quality: 75).to_bytes
    assert re_encoded.start_with?("\xFF\xD8".b)
    assert re_encoded.bytesize > 0
  end

  def test_each_pixel
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    count = 0
    image.each_pixel do |x, y, pixel|
      assert_includes 0...16, x
      assert_includes 0...16, y
      assert_valid_pixel(pixel)
      count += 1
    end

    assert_equal 16 * 16, count
  end

  def test_pixel_values_roughly_correct
    source = PureJPEG::Source::RawSource.new(16, 16) do |_x, _y|
      [255, 0, 0]
    end

    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)
    pixel = image[8, 8]

    assert_in_delta 255, pixel.r, 30, "Red channel should be close to 255"
    assert_in_delta 0, pixel.g, 30, "Green channel should be close to 0"
    assert_in_delta 0, pixel.b, 30, "Blue channel should be close to 0"
  end
end
