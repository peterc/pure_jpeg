# frozen_string_literal: true

require_relative "test_helper"

class TestIDCT < Minitest::Test
  def test_dct_round_trip
    srand(42)
    block = Array.new(64) { rand(-128.0..127.0) }
    temp = Array.new(64, 0.0)
    dct = Array.new(64, 0.0)
    out = Array.new(64, 0.0)
    temp2 = Array.new(64, 0.0)

    PureJPEG::DCT.forward!(block, temp, dct)
    PureJPEG::DCT.inverse!(dct, temp2, out)

    max_err = 64.times.map { |i| (block[i] - out[i]).abs }.max
    assert max_err < 1e-10, "Round-trip error should be negligible, got #{max_err}"
  end

  def test_uniform_block_forward
    # A uniform block of 100.0 should produce a single non-zero DC coefficient
    uniform = Array.new(64, 100.0)
    temp = Array.new(64, 0.0)
    dct = Array.new(64, 0.0)

    PureJPEG::DCT.forward!(uniform, temp, dct)

    assert_in_delta 800.0, dct[0], 1e-6, "DC coefficient for uniform block"
    # All AC coefficients should be zero
    (1...64).each do |i|
      assert_in_delta 0.0, dct[i], 1e-10, "AC[#{i}] should be zero for uniform block"
    end
  end

  def test_uniform_block_round_trip
    uniform = Array.new(64, 100.0)
    temp = Array.new(64, 0.0)
    dct = Array.new(64, 0.0)
    out = Array.new(64, 0.0)
    temp2 = Array.new(64, 0.0)

    PureJPEG::DCT.forward!(uniform, temp, dct)
    PureJPEG::DCT.inverse!(dct, temp2, out)

    out.each_with_index do |v, i|
      assert_in_delta 100.0, v, 1e-6, "All values should be 100.0, index #{i} was #{v}"
    end
  end
end
