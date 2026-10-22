# frozen_string_literal: true

require_relative "test_helper"

class TestDecoderValidation < Minitest::Test
  include TestHelper

  def setup
    @data = PureJPEG.encode(gradient_source(16, 16)).to_bytes
    @sof = @data.index("\xff\xc0".b)
    @sos = @data.index("\xff\xda".b)
  end

  def patch(offset, value, data = @data)
    data.dup.tap { |bytes| bytes.setbyte(offset, value) }
  end

  def test_missing_frame_and_scan_raise_decode_error
    ["\xff\xd8\xff\xd9".b, @data[0...@sos] + "\xff\xd9".b].each do |data|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
    end
  end

  def test_binary_garbage_does_not_get_treated_as_a_path
    ["\0bad jpeg".b, "\xfe\x00".b].each do |data|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
      assert_raises(PureJPEG::DecodeError) { PureJPEG.info(data) }
    end
  end

  def test_frame_validation
    [patch(@sof + 4, 12), patch(@sof + 11, 0), patch(@sof + 11, 0x51),
     patch(@sof + 13, 1), patch(@sof + 1, 0xc1)].each do |data|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
    end
  end

  def test_scan_validation
    [patch(@sos + 5, 99), patch(@sos + 7, 1), patch(@sos + 11, 1)].each do |data|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
    end
  end

  def test_progressive_scan_order_and_parameters
    data = File.binread(fixture_path("decoder/restart-444.jpg"))
    sos = data.index("\xff\xda".b)
    header_end = sos + 2 + data[sos + 2, 2].unpack1("n")
    [patch(header_end - 1, 0x10, data), patch(header_end - 2, 64, data),
     patch(header_end - 3, 1, data)].each do |malformed|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(malformed) }
    end
  end

  def test_truncated_entropy_and_missing_eoi
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(@data[0...-2]) }
    header_end = @sos + 2 + @data[@sos + 2, 2].unpack1("n")
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(@data[0...header_end] + "\xff\xd9".b) }
  end

  def test_restart_storm_raises_decode_error_without_recursion
    header_end = @sos + 2 + @data[@sos + 2, 2].unpack1("n")
    data = @data[0...header_end] + "\xff\xd0".b * 20_000 + @data[header_end..]
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
  end

  def test_missing_and_out_of_sequence_restarts
    data = File.binread(fixture_path("decoder/baseline-restart.jpg"))
    rst = data.index("\xff\xd0".b)
    refute_nil rst
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(patch(rst + 1, 0xd1, data)) }
    assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data[0...rst] + data[rst + 2..]) }
    padded = data[0...rst] + "\xff".b * 5 + data[rst..]
    assert_equal PureJPEG.read(data).packed_pixels, PureJPEG.read(padded).packed_pixels
  end

  def test_invalid_quantization_and_huffman_definitions
    dqt = @data.index("\xff\xdb".b)
    dht = @data.index("\xff\xc4".b)
    [patch(dqt + 4, 0x20), patch(dqt + 5, 0), patch(dht + 4, 0x20),
     patch(dht + 21, 12)].each do |data|
      assert_raises(PureJPEG::DecodeError) { PureJPEG.read(data) }
    end
    assert_raises(PureJPEG::DecodeError) do
      PureJPEG::Huffman::DecodeTable.new([2] + [0] * 15, [0, 1])
    end
  end

  def test_excessive_ac_run_is_rejected
    dc = PureJPEG::Huffman::DecodeTable.new([1] + [0] * 15, [0])
    ac = PureJPEG::Huffman::DecodeTable.new([1] + [0] * 15, [0xf0])
    reader = PureJPEG::BitReader.new("\0\0".b)
    assert_raises(PureJPEG::DecodeError) do
      PureJPEG::Decoder.new("").send(:decode_block, reader, dc, ac, Hash.new(0), 1, Array.new(64))
    end
  end
end
