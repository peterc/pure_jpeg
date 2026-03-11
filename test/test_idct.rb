# frozen_string_literal: true

require_relative "test_helper"

class TestIDCT < Minitest::Test
  def test_dct_round_trip
    srand(42)
    original = Array.new(64) { rand(-128..127) }
    block = original.dup

    PureJPEG::DCT.forward!(block)
    PureJPEG::DCT.inverse!(block)

    max_err = 64.times.map { |i| (original[i] - block[i]).abs }.max
    assert max_err <= 1, "Round-trip error should be <= 1, got #{max_err}"
  end

  def test_uniform_block_forward
    # A uniform block of 100 should produce a single non-zero DC coefficient
    block = Array.new(64, 100)

    PureJPEG::DCT.forward!(block)

    assert_equal 800, block[0], "DC coefficient for uniform block"
    # All AC coefficients should be zero
    (1...64).each do |i|
      assert_equal 0, block[i], "AC[#{i}] should be zero for uniform block"
    end
  end

  def test_uniform_block_round_trip
    block = Array.new(64, 100)

    PureJPEG::DCT.forward!(block)
    PureJPEG::DCT.inverse!(block)

    block.each_with_index do |v, i|
      assert_in_delta 100, v, 1, "All values should be ~100, index #{i} was #{v}"
    end
  end
end
