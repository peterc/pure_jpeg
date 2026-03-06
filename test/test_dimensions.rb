# frozen_string_literal: true

require_relative "test_helper"

class TestDimensions < Minitest::Test
  include TestHelper

  def test_color_dimensions
    [
      [8, 8], [16, 16],             # exact multiples of 8
      [7, 7], [9, 9], [15, 15],    # non-multiple-of-8
      [17, 17], [13, 21], [21, 13],
      [24, 24], [31, 31], [33, 33], # non-multiple-of-16 (4:2:0 subsampling)
      [1, 1], [2, 2], [3, 5],      # very small
      [1, 8], [8, 1], [1, 16], [16, 1],
      [4, 64], [64, 4],            # asymmetric
      [100, 8], [8, 100],
      [37, 41], [97, 53],          # odd primes
    ].each { |w, h| assert_round_trips(w, h) }
  end

  def test_grayscale_dimensions
    [[1, 1], [3, 5], [7, 7], [15, 15], [33, 33]].each do |w, h|
      assert_round_trips(w, h, grayscale: true)
    end
  end

  def test_pixel_accuracy_non_aligned_color
    w, h = 19, 23
    source = solid_source(w, h, 200, 100, 50)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    [[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1], [w / 2, h / 2]].each do |x, y|
      pixel = image[x, y]
      assert_in_delta 200, pixel.r, 30, "Red at (#{x},#{y})"
      assert_in_delta 100, pixel.g, 30, "Green at (#{x},#{y})"
      assert_in_delta 50, pixel.b, 30, "Blue at (#{x},#{y})"
    end
  end

  def test_pixel_accuracy_non_aligned_grayscale
    w, h = 11, 13
    source = solid_source(w, h, 180, 180, 180)
    data = PureJPEG.encode(source, quality: 95, grayscale: true).to_bytes
    image = PureJPEG.read(data)

    [[0, 0], [w - 1, h - 1], [w / 2, h / 2]].each do |x, y|
      pixel = image[x, y]
      assert_in_delta pixel.r, pixel.g, 0, "Grayscale channels should be equal at (#{x},#{y})"
      assert_in_delta 180, pixel.r, 20, "Value at (#{x},#{y})"
    end
  end

  def test_no_padding_leakage_color
    w, h = 10, 10
    source = PureJPEG::Source::RawSource.new(w, h) do |x, y|
      if x == 0 || y == 0 || x == w - 1 || y == h - 1
        [255, 0, 0]
      else
        [0, 0, 255]
      end
    end

    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    assert_equal w, image.width
    assert_equal h, image.height

    h.times do |y|
      w.times do |x|
        assert_valid_pixel(image[x, y])
      end
    end
  end

  private

  def solid_source(width, height, r, g, b)
    PureJPEG::Source::RawSource.new(width, height) do |_x, _y|
      [r, g, b]
    end
  end

  def assert_round_trips(width, height, grayscale: false)
    source = gradient_source(width, height)
    data = PureJPEG.encode(source, quality: 90, grayscale: grayscale).to_bytes

    assert data.start_with?("\xFF\xD8".b), "#{width}x#{height}: missing SOI"
    assert data.end_with?("\xFF\xD9".b), "#{width}x#{height}: missing EOI"

    image = PureJPEG.read(data)
    assert_equal width, image.width, "#{width}x#{height}: decoded width mismatch"
    assert_equal height, image.height, "#{width}x#{height}: decoded height mismatch"

    assert_valid_pixel(image[0, 0])
    assert_valid_pixel(image[width - 1, height - 1])

    if grayscale
      pixel = image[0, 0]
      assert_equal pixel.r, pixel.g, "#{width}x#{height}: grayscale channels should be equal"
      assert_equal pixel.g, pixel.b, "#{width}x#{height}: grayscale channels should be equal"
    end
  end
end
