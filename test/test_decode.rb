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

  def test_each_rgb
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    count = 0
    image.each_rgb do |x, y, r, g, b|
      assert_includes 0...16, x
      assert_includes 0...16, y
      assert_includes 0..255, r
      assert_includes 0..255, g
      assert_includes 0..255, b
      # Should match each_pixel results
      pixel = image[x, y]
      assert_equal pixel.r, r
      assert_equal pixel.g, g
      assert_equal pixel.b, b
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

  def test_decode_external_jpeg
    path = File.expand_path("../examples/a.jpg", __dir__)
    image = PureJPEG.read(path)

    assert_equal 1024, image.width
    assert_equal 1024, image.height

    # Spot-check pixels at corners and center
    [[0, 0], [1023, 0], [0, 1023], [1023, 1023], [512, 512]].each do |x, y|
      assert_valid_pixel(image[x, y])
    end

    # Verify all packed pixels are valid RGB values (avoids 1M Pixel allocations)
    packed = image.packed_pixels
    assert_equal 1024 * 1024, packed.length
    packed.each do |color|
      r = (color >> 16) & 0xFF
      g = (color >> 8) & 0xFF
      b = color & 0xFF
      assert_includes 0..255, r
      assert_includes 0..255, g
      assert_includes 0..255, b
    end
  end

  def test_re_encode_external_jpeg
    path = File.expand_path("../examples/a.jpg", __dir__)
    image = PureJPEG.read(path)

    re_encoded = PureJPEG.encode(image, quality: 75).to_bytes
    assert re_encoded.start_with?("\xFF\xD8".b)
    assert re_encoded.end_with?("\xFF\xD9".b)

    # Decode the re-encoded output to verify it survives a full round trip
    image2 = PureJPEG.read(re_encoded)
    assert_equal 1024, image2.width
    assert_equal 1024, image2.height
    assert_valid_pixel(image2[512, 512])
  end

  # --- Progressive JPEG tests ---

  def test_decode_progressive_jpeg
    path = File.expand_path("../examples/a-progressive.jpg", __dir__)
    image = PureJPEG.read(path)

    assert_equal 1024, image.width
    assert_equal 1024, image.height

    [[0, 0], [512, 512], [1023, 1023]].each do |x, y|
      assert_valid_pixel(image[x, y])
    end
  end

  def test_re_encode_progressive_jpeg
    path = File.expand_path("../examples/a-progressive.jpg", __dir__)
    image = PureJPEG.read(path)

    re_encoded = PureJPEG.encode(image, quality: 75).to_bytes
    assert re_encoded.start_with?("\xFF\xD8".b)
    assert re_encoded.end_with?("\xFF\xD9".b)

    image2 = PureJPEG.read(re_encoded)
    assert_equal 1024, image2.width
    assert_equal 1024, image2.height
    assert_valid_pixel(image2[512, 512])
  end

  # --- Malformed input tests ---

  def test_garbage_data_raises_decode_error
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read("not a jpeg at all".b) }
  end

  def test_truncated_header_raises_decode_error
    # SOI marker only, nothing else
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read("\xFF\xD8".b) }
  end

  def test_truncated_scan_data_raises_decode_error
    # Encode a valid JPEG then chop off the last half of the data
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    truncated = data[0, data.bytesize / 2]
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(truncated) }
  end

  def test_empty_data_raises_decode_error
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read("".b) }
  end

  # --- 16-bit quantization table test ---

  def test_decode_16bit_quantization_table
    # Build a valid JPEG but patch the DQT to use 16-bit precision.
    # Encode a small image first to get valid JPEG bytes.
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    bytes = data.dup

    # Find the DQT marker (FF DB)
    dqt_pos = bytes.index("\xFF\xDB".b)
    refute_nil dqt_pos, "Should find DQT marker"

    # DQT structure: FF DB, 2-byte length, then (precision_and_id, 64 values...)
    # For 8-bit: precision_and_id = 0x00 (precision=0, id=0), 64 bytes
    # For 16-bit: precision_and_id = 0x10 (precision=1, id=0), 64 * 2 bytes
    length_pos = dqt_pos + 2
    old_length = (bytes.getbyte(length_pos) << 8) | bytes.getbyte(length_pos + 1)
    info_pos = length_pos + 2

    # Read the original 8-bit table values
    old_table = (0...64).map { |i| bytes.getbyte(info_pos + 1 + i) }

    # Build a 16-bit DQT segment: precision=1, id=0, then 64 x 2-byte values
    new_segment = "\xFF\xDB".b
    new_length = 2 + 1 + 64 * 2  # length field includes itself + info byte + 128 bytes
    new_segment << [new_length].pack("n")
    new_segment << [0x10].pack("C")  # precision=1, table_id=0
    old_table.each { |v| new_segment << [v].pack("n") }

    # Replace the old DQT segment with the new one
    old_segment_size = 2 + old_length  # marker + length + data
    patched = bytes[0...dqt_pos] + new_segment + bytes[(dqt_pos + old_segment_size)..]

    # Decode should work with the 16-bit table
    image = PureJPEG.read(patched)
    assert_equal 16, image.width
    assert_equal 16, image.height
    assert_valid_pixel(image[0, 0])
  end
end
