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
    path = fixture_path("a.jpg")
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
    path = fixture_path("a.jpg")
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
    path = fixture_path("a-progressive.jpg")
    image = PureJPEG.read(path)

    assert_equal 1024, image.width
    assert_equal 1024, image.height

    [[0, 0], [512, 512], [1023, 1023]].each do |x, y|
      assert_valid_pixel(image[x, y])
    end
  end

  def test_re_encode_progressive_jpeg
    path = fixture_path("a-progressive.jpg")
    image = PureJPEG.read(path)

    re_encoded = PureJPEG.encode(image, quality: 75).to_bytes
    assert re_encoded.start_with?("\xFF\xD8".b)
    assert re_encoded.end_with?("\xFF\xD9".b)

    image2 = PureJPEG.read(re_encoded)
    assert_equal 1024, image2.width
    assert_equal 1024, image2.height
    assert_valid_pixel(image2[512, 512])
  end

  def test_image_pixel_setter
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 95).to_bytes
    image = PureJPEG.read(data)

    new_pixel = PureJPEG::Source::Pixel.new(42, 100, 200)
    image[5, 5] = new_pixel

    result = image[5, 5]
    assert_equal 42, result.r
    assert_equal 100, result.g
    assert_equal 200, result.b
  end

  def test_image_pixel_getter_rejects_out_of_bounds_coordinates
    image = PureJPEG::Image.new(2, 2, [0x112233, 0x445566, 0x778899, 0xaabbcc])

    [[-1, 0], [0, -1], [2, 0], [0, 2], [1.5, 0], [0, "1"]].each do |x, y|
      error = assert_raises(IndexError) { image[x, y] }
      assert_equal "Pixel coordinate out of bounds: #{x.inspect}, #{y.inspect}", error.message
    end
  end

  def test_image_pixel_setter_rejects_out_of_bounds_coordinates
    image = PureJPEG::Image.new(2, 2, [0x112233, 0x445566, 0x778899, 0xaabbcc])
    pixel = PureJPEG::Source::Pixel.new(1, 2, 3)

    [[-1, 0], [0, -1], [2, 0], [0, 2], [1.5, 0], [0, "1"]].each do |x, y|
      error = assert_raises(IndexError) { image[x, y] = pixel }
      assert_equal "Pixel coordinate out of bounds: #{x.inspect}, #{y.inspect}", error.message
    end
  end

  def test_chunky_png_source_with_fake_image
    # Quack like ChunkyPNG::Image without requiring the gem
    fake_image = Struct.new(:width, :height, :pixels).new(
      2, 2,
      [
        (255 << 24) | (0 << 16) | (0 << 8) | 255,   # red
        (0 << 24) | (255 << 16) | (0 << 8) | 255,   # green
        (0 << 24) | (0 << 16) | (255 << 8) | 255,   # blue
        (128 << 24) | (128 << 16) | (128 << 8) | 255 # gray
      ]
    )

    source = PureJPEG::Source::ChunkyPNGSource.new(fake_image)
    assert_equal 2, source.width
    assert_equal 2, source.height

    pixel = source[0, 0]
    assert_equal 255, pixel.r
    assert_equal 0, pixel.g
    assert_equal 0, pixel.b

    pixel = source[1, 0]
    assert_equal 0, pixel.r
    assert_equal 255, pixel.g
    assert_equal 0, pixel.b
  end

  def test_from_chunky_png_convenience_method
    fake_image = Struct.new(:width, :height, :pixels).new(
      8, 8,
      Array.new(64) { (128 << 24) | (128 << 16) | (128 << 8) | 255 }
    )

    encoder = PureJPEG.from_chunky_png(fake_image, quality: 75)
    data = encoder.to_bytes
    assert data.start_with?("\xFF\xD8".b)
    assert data.end_with?("\xFF\xD9".b)
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

  def test_decode_color_when_sof_components_are_reordered
    source = PureJPEG::Source::RawSource.new(16, 16) do |x, y|
      [x * 12, y * 12, 80]
    end
    data = PureJPEG.encode(source, quality: 85).to_bytes

    reordered = reorder_sof_components(data, 1, 0, 2)

    original_image = PureJPEG.read(data)
    reordered_image = PureJPEG.read(reordered)

    assert_equal original_image.width, reordered_image.width
    assert_equal original_image.height, reordered_image.height
    assert_equal original_image.packed_pixels, reordered_image.packed_pixels
  end

  def test_decode_color_with_nonstandard_component_ids
    source = PureJPEG::Source::RawSource.new(16, 16) do |x, y|
      [x * 12, y * 12, 80]
    end
    data = PureJPEG.encode(source, quality: 85).to_bytes

    remapped = remap_component_ids(data, 1 => 0, 2 => 1, 3 => 2)

    original_image = PureJPEG.read(data)
    remapped_image = PureJPEG.read(remapped)

    assert_equal original_image.width, remapped_image.width
    assert_equal original_image.height, remapped_image.height
    assert_equal original_image.packed_pixels, remapped_image.packed_pixels
  end

  def test_missing_quantization_table_raises_decode_error
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes
    patched = patch_sof_quant_table_id(data, 5)

    error = assert_raises(PureJPEG::DecodeError) { PureJPEG.read(patched) }
    assert_match(/missing quantization table 5/, error.message)
  end

  def test_decoded_image_carries_icc_profile
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    profile_data = "test-icc-profile-bytes"
    data_with_icc = inject_icc_profile(data, profile_data)

    image = PureJPEG.read(data_with_icc)

    assert_equal profile_data, image.icc_profile
  end

  def test_decoded_image_without_icc_profile
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85).to_bytes

    image = PureJPEG.read(data)

    assert_nil image.icc_profile
  end

  def test_missing_huffman_table_raises_decode_error
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes
    patched = patch_sos_table_selectors(data, 0, 2)

    error = assert_raises(PureJPEG::DecodeError) { PureJPEG.read(patched) }
    assert_match(/missing AC Huffman table 2/, error.message)
  end

  def test_decode_fixture_with_444_chroma_sampling
    data = File.binread(fixture_path("subsampling_444.jpg"))

    assert_equal [[1, 1, 1, 0], [2, 1, 1, 1], [3, 1, 1, 1]], sof0_components(data)

    image = PureJPEG.read(data)
    assert_equal 31, image.width
    assert_equal 23, image.height
    assert_fixture_colors(image)
  end

  def test_decode_fixture_with_422_chroma_sampling
    data = File.binread(fixture_path("subsampling_422.jpg"))

    assert_equal [[1, 2, 1, 0], [2, 1, 1, 1], [3, 1, 1, 1]], sof0_components(data)

    image = PureJPEG.read(data)
    assert_equal 31, image.width
    assert_equal 23, image.height
    assert_fixture_colors(image)
  end

  def test_decode_fixture_with_420_chroma_sampling
    data = File.binread(fixture_path("subsampling_420.jpg"))

    assert_equal [[1, 2, 2, 0], [2, 1, 1, 1], [3, 1, 1, 1]], sof0_components(data)

    image = PureJPEG.read(data)
    assert_equal 31, image.width
    assert_equal 23, image.height
    assert_fixture_colors(image)
  end

  private

  def sof0_components(data)
    sof_pos = data.index("\xFF\xC0".b)
    refute_nil sof_pos, "Should find SOF0 marker"

    num_components = data.getbyte(sof_pos + 9)
    Array.new(num_components) do |i|
      offset = sof_pos + 10 + (i * 3)
      sampling = data.getbyte(offset + 1)
      [data.getbyte(offset), sampling >> 4, sampling & 0x0F, data.getbyte(offset + 2)]
    end
  end

  def assert_fixture_colors(image)
    assert_rgb_near image[3, 3], 255, 0, 0
    assert_rgb_near image[27, 3], 0, 255, 0
    assert_rgb_near image[3, 19], 0, 0, 255
    assert_rgb_near image[27, 19], 255, 255, 0
    assert_rgb_near image[15, 11], 0, 255, 255
  end

  def assert_rgb_near(pixel, r, g, b)
    assert_in_delta r, pixel.r, 12
    assert_in_delta g, pixel.g, 12
    assert_in_delta b, pixel.b, 12
  end

  def reorder_sof_components(data, *order)
    bytes = data.dup
    sof_pos = bytes.index("\xFF\xC0".b)
    refute_nil sof_pos, "Should find SOF0 marker"

    num_components = bytes.getbyte(sof_pos + 9)
    descriptors_pos = sof_pos + 10
    descriptors = Array.new(num_components) do |i|
      bytes.byteslice(descriptors_pos + i * 3, 3)
    end

    order.each_with_index do |source_index, dest_index|
      bytes[descriptors_pos + dest_index * 3, 3] = descriptors[source_index]
    end

    bytes
  end

  def patch_sof_quant_table_id(data, qt_id)
    bytes = data.dup
    sof_pos = bytes.index("\xFF\xC0".b)
    refute_nil sof_pos, "Should find SOF0 marker"

    num_components = bytes.getbyte(sof_pos + 9)
    first_component_qt_pos = sof_pos + 10 + (num_components * 3) - 1
    bytes.setbyte(first_component_qt_pos, qt_id)
    bytes
  end

  def patch_sos_table_selectors(data, dc_id, ac_id)
    bytes = data.dup
    sos_pos = bytes.index("\xFF\xDA".b)
    refute_nil sos_pos, "Should find SOS marker"

    table_selector_pos = sos_pos + 6
    bytes.setbyte(table_selector_pos, (dc_id << 4) | ac_id)
    bytes
  end

  def remap_component_ids(data, mapping)
    bytes = data.dup

    sof_pos = bytes.index("\xFF\xC0".b)
    refute_nil sof_pos, "Should find SOF0 marker"
    sof_components = bytes.getbyte(sof_pos + 9)
    sof_components.times do |i|
      id_pos = sof_pos + 10 + (i * 3)
      bytes.setbyte(id_pos, mapping.fetch(bytes.getbyte(id_pos), bytes.getbyte(id_pos)))
    end

    sos_pos = bytes.index("\xFF\xDA".b)
    refute_nil sos_pos, "Should find SOS marker"
    sos_components = bytes.getbyte(sos_pos + 4)
    sos_components.times do |i|
      id_pos = sos_pos + 5 + (i * 2)
      bytes.setbyte(id_pos, mapping.fetch(bytes.getbyte(id_pos), bytes.getbyte(id_pos)))
    end

    bytes
  end

  def inject_icc_profile(jpeg_data, profile_data)
    sig = "ICC_PROFILE\0".b
    seq = 1.chr.b
    total = 1.chr.b
    payload = sig + seq + total + profile_data.b
    length = [payload.bytesize + 2].pack("n")
    app2 = "\xFF\xE2".b + length + payload

    jpeg_data[0, 2] + app2 + jpeg_data[2..]
  end
end
