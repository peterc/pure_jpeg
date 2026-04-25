# frozen_string_literal: true

require_relative "test_helper"

class TestIntegration < Minitest::Test
  include TestHelper

  def test_encode_raw_pixels_to_jpeg_file
    source = PureJPEG::Source::RawSource.new(100, 80) do |x, y|
      [x * 2, y * 3, 128]
    end

    path = "/tmp/pure_jpeg_integration_encode.jpg"
    PureJPEG.encode(source, quality: 85).write(path)

    assert File.exist?(path)
    assert File.size(path) > 100
    assert File.binread(path).start_with?("\xFF\xD8".b)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_encode_to_bytes
    source = PureJPEG::Source::RawSource.new(64, 64) do |x, y|
      [x * 4, y * 4, 128]
    end

    bytes = PureJPEG.encode(source, quality: 80).to_bytes
    assert bytes.start_with?("\xFF\xD8".b)
    assert bytes.end_with?("\xFF\xD9".b)
  end

  def test_decode_jpeg_and_read_pixels
    path = fixture_path("a.jpg")
    image = PureJPEG.read(path)

    assert_equal 1024, image.width
    assert_equal 1024, image.height

    pixel = image[512, 512]
    assert_kind_of PureJPEG::Source::Pixel, pixel
    assert_includes 0..255, pixel.r
    assert_includes 0..255, pixel.g
    assert_includes 0..255, pixel.b
  end

  def test_decode_progressive_jpeg
    path = fixture_path("a-progressive.jpg")
    image = PureJPEG.read(path)

    assert_equal 1024, image.width
    assert_equal 1024, image.height
    assert_valid_pixel(image[512, 512])
  end

  def test_decode_from_bytes
    path = fixture_path("a.jpg")
    bytes = File.binread(path)
    image = PureJPEG.read(bytes)

    assert_equal 1024, image.width
    assert_equal 1024, image.height
  end

  def test_iterate_pixels
    source = PureJPEG::Source::RawSource.new(16, 16) { |_x, _y| [200, 100, 50] }
    bytes = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(bytes)

    pixels = []
    image.each_pixel do |x, y, pixel|
      pixels << [x, y, pixel.r, pixel.g, pixel.b]
    end

    assert_equal 256, pixels.length
    assert_equal [0, 0], pixels.first[0..1]
    assert_equal [15, 15], pixels.last[0..1]
  end

  def test_iterate_rgb_without_allocations
    source = PureJPEG::Source::RawSource.new(16, 16) { |_x, _y| [200, 100, 50] }
    bytes = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(bytes)

    count = 0
    image.each_rgb do |x, y, r, g, b|
      assert_includes 0..255, r
      assert_includes 0..255, g
      assert_includes 0..255, b
      count += 1
    end

    assert_equal 256, count
  end

  def test_decode_and_re_encode_at_lower_quality
    path = fixture_path("a.jpg")
    original = PureJPEG.read(path)

    smaller = PureJPEG.encode(original, quality: 30).to_bytes
    larger = PureJPEG.encode(original, quality: 95).to_bytes

    assert smaller.bytesize < larger.bytesize

    re_decoded = PureJPEG.read(smaller)
    assert_equal original.width, re_decoded.width
    assert_equal original.height, re_decoded.height
  end

  def test_encode_grayscale
    source = PureJPEG::Source::RawSource.new(64, 64) do |x, y|
      v = ((x + y) * 2).clamp(0, 255)
      [v, v, v]
    end

    bytes = PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes
    image = PureJPEG.read(bytes)

    pixel = image[32, 32]
    assert_equal pixel.r, pixel.g
    assert_equal pixel.g, pixel.b
  end

  def test_custom_quantization_table
    flat_table = Array.new(64, 10)

    source = PureJPEG::Source::RawSource.new(32, 32) { |_x, _y| [100, 150, 200] }
    bytes = PureJPEG.encode(source, luminance_table: flat_table, chrominance_table: flat_table).to_bytes

    image = PureJPEG.read(bytes)
    assert_equal 32, image.width
    pixel = image[16, 16]
    assert_in_delta 100, pixel.r, 20
    assert_in_delta 150, pixel.g, 20
    assert_in_delta 200, pixel.b, 20
  end

  def test_invalid_jpeg_raises_decode_error
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read("not a jpeg".b) }
  end

  def test_invalid_quantization_table_raises_argument_error
    bad_table = Array.new(32, 10) # too short
    source = PureJPEG::Source::RawSource.new(8, 8) { |_x, _y| [0, 0, 0] }

    assert_raises(ArgumentError) { PureJPEG.encode(source, luminance_table: bad_table) }
  end

  def test_encoder_rejects_zero_dimensions
    source = PureJPEG::Source::RawSource.new(0, 10)
    assert_raises(ArgumentError) { PureJPEG.encode(source).to_bytes }
  end

  def test_encoder_rejects_oversized_dimensions
    source = PureJPEG::Source::RawSource.new(8193, 100)
    assert_raises(ArgumentError) { PureJPEG.encode(source).to_bytes }
  end

  def test_raw_source_without_block_encodes_black
    source = PureJPEG::Source::RawSource.new(16, 16)
    bytes = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(bytes)

    pixel = image[8, 8]
    assert_in_delta 0, pixel.r, 10
    assert_in_delta 0, pixel.g, 10
    assert_in_delta 0, pixel.b, 10
  end
end
