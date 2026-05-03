# frozen_string_literal: true

require_relative "test_helper"

class TestEncode < Minitest::Test
  include TestHelper

  def test_gradient_encodes_to_valid_jpeg
    source = gradient_source(64, 64)
    data = PureJPEG.encode(source, quality: 75).to_bytes

    assert data.start_with?("\xFF\xD8".b), "Should start with SOI marker"
    assert data.end_with?("\xFF\xD9".b), "Should end with EOI marker"
    assert data.bytesize > 100, "Should produce non-trivial output"
  end

  def test_pattern_encodes_to_valid_jpeg
    source = PureJPEG::Source::RawSource.new(128, 128) do |x, y|
      r = ((Math.sin(x * 0.1) + 1) * 127).round
      g = ((Math.sin(y * 0.1) + 1) * 127).round
      b = ((Math.sin((x + y) * 0.05) + 1) * 127).round
      [r, g, b]
    end

    data = PureJPEG.encode(source, quality: 90).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_write_to_file
    source = gradient_source(32, 32)
    path = "/tmp/pure_jpeg_test_encode.jpg"
    PureJPEG.encode(source, quality: 80).write(path)

    assert File.exist?(path)
    assert File.size(path) > 0
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_quality_affects_size
    source = gradient_source(64, 64)
    low = PureJPEG.encode(source, quality: 10).to_bytes
    high = PureJPEG.encode(source, quality: 95).to_bytes

    assert high.bytesize > low.bytesize, "Higher quality should produce larger output"
  end

  def test_invalid_quality_raises_argument_error
    source = gradient_source(8, 8)

    [0, 101, "85", nil].each do |quality|
      error = assert_raises(ArgumentError) do
        PureJPEG.encode(source, quality: quality)
      end
      assert_equal "quality must be an integer between 1 and 100", error.message
    end
  end

  def test_invalid_chroma_quality_raises_argument_error
    source = gradient_source(8, 8)

    [0, 101, "85"].each do |chroma_quality|
      error = assert_raises(ArgumentError) do
        PureJPEG.encode(source, chroma_quality: chroma_quality)
      end
      assert_equal "chroma_quality must be an integer between 1 and 100", error.message
    end
  end

  def test_optimized_huffman_can_reduce_color_output_size
    source = PureJPEG::Source::RawSource.new(128, 128) do |x, y|
      r = ((Math.sin(x * 0.1) + 1) * 127).round
      g = ((Math.sin(y * 0.1) + 1) * 127).round
      b = ((Math.sin((x + y) * 0.05) + 1) * 127).round
      [r, g, b]
    end

    standard = PureJPEG.encode(source, quality: 90).to_bytes
    optimized = PureJPEG.encode(source, quality: 90, optimize_huffman: true).to_bytes

    assert_operator optimized.bytesize, :<=, standard.bytesize

    standard_image = PureJPEG.read(standard)
    optimized_image = PureJPEG.read(optimized)
    assert_equal standard_image.packed_pixels, optimized_image.packed_pixels
  end

  def test_invalid_luminance_table_raises_argument_error
    source = gradient_source(8, 8)

    # Wrong length
    assert_raises(ArgumentError) do
      PureJPEG.encode(source, luminance_table: Array.new(32, 10))
    end

    # Value out of range
    assert_raises(ArgumentError) do
      PureJPEG.encode(source, luminance_table: Array.new(64, 0))
    end

    # Not an array
    assert_raises(ArgumentError) do
      PureJPEG.encode(source, luminance_table: "not a table")
    end
  end

  def test_invalid_chrominance_table_raises_argument_error
    source = gradient_source(8, 8)

    assert_raises(ArgumentError) do
      PureJPEG.encode(source, chrominance_table: Array.new(64, 256))
    end
  end

  def test_optimized_huffman_can_reduce_grayscale_output_size
    source = PureJPEG::Source::RawSource.new(128, 128) do |x, y|
      value = (((Math.sin(x * 0.12) + Math.cos(y * 0.08) + 2) / 4) * 255).round
      [value, value, value]
    end

    standard = PureJPEG.encode(source, quality: 90, grayscale: true).to_bytes
    optimized = PureJPEG.encode(source, quality: 90, grayscale: true, optimize_huffman: true).to_bytes

    assert_operator optimized.bytesize, :<=, standard.bytesize

    standard_image = PureJPEG.read(standard)
    optimized_image = PureJPEG.read(optimized)
    assert_equal standard_image.packed_pixels, optimized_image.packed_pixels
  end
end
