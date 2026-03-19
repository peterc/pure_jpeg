# frozen_string_literal: true

require_relative "test_helper"

class TestRawSource < Minitest::Test
  def test_width_and_height
    source = PureJPEG::Source::RawSource.new(10, 20) { |_x, _y| [0, 0, 0] }
    assert_equal 10, source.width
    assert_equal 20, source.height
  end

  def test_block_constructor
    source = PureJPEG::Source::RawSource.new(4, 4) do |x, y|
      [x * 60, y * 60, 100]
    end

    pixel = source[3, 2]
    assert_equal 180, pixel.r
    assert_equal 120, pixel.g
    assert_equal 100, pixel.b
  end

  def test_set_method
    source = PureJPEG::Source::RawSource.new(4, 4)
    source.set(2, 3, 10, 20, 30)

    pixel = source[2, 3]
    assert_equal 10, pixel.r
    assert_equal 20, pixel.g
    assert_equal 30, pixel.b
  end

  def test_set_overwrites_block_value
    source = PureJPEG::Source::RawSource.new(4, 4) { |_x, _y| [255, 255, 255] }
    source.set(1, 1, 0, 0, 0)

    assert_equal 0, source[1, 1].r
    assert_equal 255, source[0, 0].r
  end

  def test_without_block_pixels_are_black
    source = PureJPEG::Source::RawSource.new(2, 2)
    pixel = source[0, 0]
    assert_equal 0, pixel.r
    assert_equal 0, pixel.g
    assert_equal 0, pixel.b
  end

  def test_default_pixels_are_not_shared
    source = PureJPEG::Source::RawSource.new(2, 2)

    source[0, 0].r = 7

    assert_equal 7, source[0, 0].r
    assert_equal 0, source[1, 1].r
  end

  def test_pixel_responds_to_rgb
    source = PureJPEG::Source::RawSource.new(1, 1) { |_x, _y| [1, 2, 3] }
    pixel = source[0, 0]

    assert_respond_to pixel, :r
    assert_respond_to pixel, :g
    assert_respond_to pixel, :b
  end

  def test_encodable
    source = PureJPEG::Source::RawSource.new(16, 16) do |x, y|
      [x * 16, y * 16, 128]
    end

    data = PureJPEG.encode(source, quality: 90).to_bytes
    assert data.start_with?("\xFF\xD8".b)

    image = PureJPEG.read(data)
    assert_equal 16, image.width
    assert_equal 16, image.height
  end
end
