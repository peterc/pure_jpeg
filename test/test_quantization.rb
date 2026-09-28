# frozen_string_literal: true

require_relative "test_helper"

class TestQuantization < Minitest::Test
  def test_combined_quantization_matches_separate_stages
    rng = Random.new(1234)
    actual = Array.new(64)
    quantized = Array.new(64)
    expected = Array.new(64)

    100.times do
      table = Array.new(64) { rng.rand(1..255) }
      block = Array.new(64) { rng.rand(-2048..2047) }
      PureJPEG::Quantization.quantize!(block, table, quantized)
      PureJPEG::Zigzag.reorder!(quantized, expected)

      assert_same actual, PureJPEG::Quantization.quantize_zigzag!(block, table, actual)
      assert_equal expected, actual
    end
  end

  def test_combined_quantization_preserves_rounding_at_half_steps
    1.upto(255) do |divisor|
      block = Array.new(64) { |i| (i - 32) * divisor / 2 }
      table = Array.new(64, divisor)
      expected = PureJPEG::Zigzag.reorder!(
        PureJPEG::Quantization.quantize!(block, table, Array.new(64)), Array.new(64)
      )
      assert_equal expected, PureJPEG::Quantization.quantize_zigzag!(block, table, Array.new(64))
    end
  end

  def test_combined_dequantization_reads_the_selected_progressive_block
    rng = Random.new(5678)
    blocks = Array.new(3 * 64) { rng.rand(-2048..2047) }
    table = Array.new(64) { rng.rand(1..65535) }
    actual = Array.new(64)

    [0, 64, 128].each do |offset|
      raster = PureJPEG::Zigzag.unreorder!(blocks.slice(offset, 64), Array.new(64))
      expected = PureJPEG::Quantization.dequantize!(raster, table, Array.new(64))
      assert_same actual, PureJPEG::Quantization.dequantize_zigzag!(blocks, table, actual, offset)
      assert_equal expected, actual
    end
  end
end
