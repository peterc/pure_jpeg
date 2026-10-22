# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class TestDecodeLimits < Minitest::Test
  include TestHelper

  def test_default_limit_rejects_oversized_frames_before_reading_further
    assert_equal 8_000_000, PureJPEG::MAX_PIXELS
    [false, true].each do |progressive|
      # No EOI or scan follows: the size error must take precedence over truncation.
      data = frame_header(4000, 2001, progressive: progressive)
      decoders.each do |decode|
        error = assert_raises(PureJPEG::DecodeError) { decode.call(data) }
        assert_equal "Image too large: 4000x2001 (max 8000000 pixels)", error.message
      end
    end
  end

  def test_exact_default_limit_is_accepted_by_size_check
    [false, true].each do |progressive|
      data = frame_header(4000, 2000, progressive: progressive) + "\xff\xd9".b
      decoders.each do |decode|
        # A header-only JPEG passes the size check but fails scan validation,
        # so testing the real default boundary never allocates large buffers.
        error = assert_raises(PureJPEG::DecodeError) { decode.call(data) }
        assert_equal "JPEG scan data not found", error.message
      end
    end
  end

  def test_limit_can_be_raised_above_default
    [false, true].each do |progressive|
      data = frame_header(4000, 2001, progressive: progressive) + "\xff\xd9".b
      decoders.each do |decode|
        error = assert_raises(PureJPEG::DecodeError) do
          decode.call(data, max_pixels: 8_004_000)
        end
        assert_equal "JPEG scan data not found", error.message
      end
    end
  end

  def test_custom_limits_on_complete_baseline_and_progressive_images
    baseline = PureJPEG.encode(gradient_source(16, 16)).to_bytes
    progressive = File.binread(fixture_path("decoder/restart-444.jpg"))
    assert PureJPEG.info(progressive).progressive

    [baseline, progressive].each do |data|
      expected = PureJPEG.read(data)
      pixels = expected.width * expected.height
      decoders.each do |decode|
        error = assert_raises(PureJPEG::DecodeError) do
          decode.call(data, max_pixels: pixels - 1)
        end
        assert_includes error.message, "max #{pixels - 1} pixels"
        actual = decode.call(data, max_pixels: pixels)
        assert_equal expected.packed_pixels, actual.packed_pixels
      end
      # A stricter per-call limit must not change later calls' defaults.
      assert_equal expected.packed_pixels, PureJPEG.read(data).packed_pixels
    end
  end

  def test_file_paths_accept_custom_limit
    data = PureJPEG.encode(gradient_source(16, 16)).to_bytes
    Tempfile.create(["pure-jpeg-limit", ".jpg"]) do |file|
      file.binmode
      file.write(data)
      file.flush
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(file.path, max_pixels: 255) }
      assert_equal 256, PureJPEG.read(file.path, max_pixels: 256).packed_pixels.length
      assert_raises(PureJPEG::DecodeError) { PureJPEG::Decoder.decode(file.path, max_pixels: 255) }
      assert_equal 256, PureJPEG::Decoder.decode(file.path, max_pixels: 256).packed_pixels.length
    end
  end

  def test_invalid_limits_raise_argument_error
    [nil, false, 0, -1, 8_000_000.0, "8000000"].each do |limit|
      decoders.each do |decode|
        error = assert_raises(ArgumentError) { decode.call("".b, max_pixels: limit) }
        assert_equal "max_pixels must be a positive Integer", error.message
      end
    end
  end

  def test_raising_pixel_limit_does_not_bypass_axis_limit
    data = frame_header(8193, 1) + "\xff\xd9".b
    decoders.each do |decode|
      error = assert_raises(PureJPEG::DecodeError) { decode.call(data, max_pixels: 100_000_000) }
      assert_includes error.message, "max 8192x8192"
    end
  end

  def test_info_can_inspect_images_above_decode_limit
    info = PureJPEG.info(frame_header(8192, 8192))
    assert_equal 8192, info.width
    assert_equal 8192, info.height
  end

  private

  def decoders
    [PureJPEG.method(:read), PureJPEG::Decoder.method(:decode),
     ->(data, **options) { PureJPEG::Decoder.new(data, **options).decode }]
  end

  def frame_header(width, height, progressive: false)
    # SOI and a complete one-component SOF, without scan data or EOI.
    "\xff\xd8".b + [255, progressive ? 0xc2 : 0xc0, 11, 8, height, width, 1, 1, 0x11, 0].pack("CCnCnnCCCC")
  end
end
