# frozen_string_literal: true

require_relative "test_helper"

class TestDimensions < Minitest::Test
  include TestHelper

  # --- Exact multiples of 8 (baseline, should always work) ---

  def test_8x8
    assert_round_trips(8, 8)
  end

  def test_16x16
    assert_round_trips(16, 16)
  end

  # --- Non-multiple-of-8 dimensions ---

  def test_7x7
    assert_round_trips(7, 7)
  end

  def test_9x9
    assert_round_trips(9, 9)
  end

  def test_15x15
    assert_round_trips(15, 15)
  end

  def test_17x17
    assert_round_trips(17, 17)
  end

  def test_13x21
    assert_round_trips(13, 21)
  end

  def test_21x13
    assert_round_trips(21, 13)
  end

  # --- Non-multiple-of-16 (matters for 4:2:0 chroma subsampling) ---

  def test_24x24_color
    assert_round_trips(24, 24)
  end

  def test_31x31_color
    assert_round_trips(31, 31)
  end

  def test_33x33_color
    assert_round_trips(33, 33)
  end

  # --- Very small images ---

  def test_1x1
    assert_round_trips(1, 1)
  end

  def test_1x1_grayscale
    assert_round_trips(1, 1, grayscale: true)
  end

  def test_2x2
    assert_round_trips(2, 2)
  end

  def test_1x8
    assert_round_trips(1, 8)
  end

  def test_8x1
    assert_round_trips(8, 1)
  end

  def test_1x16
    assert_round_trips(1, 16)
  end

  def test_16x1
    assert_round_trips(16, 1)
  end

  def test_3x5
    assert_round_trips(3, 5)
  end

  # --- Asymmetric dimensions ---

  def test_wide_4x64
    assert_round_trips(4, 64)
  end

  def test_tall_64x4
    assert_round_trips(64, 4)
  end

  def test_wide_100x8
    assert_round_trips(100, 8)
  end

  def test_tall_8x100
    assert_round_trips(8, 100)
  end

  # --- Odd primes (worst case for block alignment) ---

  def test_37x41
    assert_round_trips(37, 41)
  end

  def test_97x53
    assert_round_trips(97, 53)
  end

  # --- Grayscale variants (no subsampling, only 8x8 block alignment matters) ---

  def test_7x7_grayscale
    assert_round_trips(7, 7, grayscale: true)
  end

  def test_15x15_grayscale
    assert_round_trips(15, 15, grayscale: true)
  end

  def test_33x33_grayscale
    assert_round_trips(33, 33, grayscale: true)
  end

  def test_3x5_grayscale
    assert_round_trips(3, 5, grayscale: true)
  end

  # --- Pixel accuracy for non-aligned dimensions ---

  def test_pixel_accuracy_non_aligned_color
    w, h = 19, 23
    source = solid_source(w, h, 200, 100, 50)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    # Check corners and center
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

  # --- Edge pixels are within image bounds (no padding leakage) ---

  def test_no_padding_leakage_color
    w, h = 10, 10
    source = PureJPEG::Source::RawSource.new(w, h) do |x, y|
      # Bright interior, distinct border
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

    # All pixels should be accessible without error
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

    # Verify all pixels are accessible and valid
    assert_valid_pixel(image[0, 0])
    assert_valid_pixel(image[width - 1, height - 1])

    if grayscale
      pixel = image[0, 0]
      assert_equal pixel.r, pixel.g, "#{width}x#{height}: grayscale channels should be equal"
      assert_equal pixel.g, pixel.b, "#{width}x#{height}: grayscale channels should be equal"
    end
  end
end
