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
