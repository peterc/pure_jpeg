# frozen_string_literal: true

require_relative "test_helper"

class TestCreative < Minitest::Test
  include TestHelper

  def setup
    @source = gradient_source(64, 64)
  end

  def test_scrambled_quantization
    data = PureJPEG.encode(@source, quality: 20, scramble_quantization: true).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_chroma_crush
    data = PureJPEG.encode(@source, quality: 90, chroma_quality: 5).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_luma_crush
    data = PureJPEG.encode(@source, quality: 10, chroma_quality: 95).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_dc_only
    dc_only = [1] + [255] * 63
    data = PureJPEG.encode(@source, luminance_table: dc_only, chrominance_table: dc_only).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_inverted_emphasis
    inverter = ->(table, _channel) {
      max = table.max
      table.map { |v| [max + 1 - v, 1].max }
    }
    data = PureJPEG.encode(@source, quality: 30, quantization_modifier: inverter).to_bytes
    assert data.start_with?("\xFF\xD8".b)
  end

  def test_quantization_modifier_receives_channel
    channels_seen = []
    modifier = ->(table, channel) {
      channels_seen << channel
      table
    }
    PureJPEG.encode(@source, quality: 50, quantization_modifier: modifier).to_bytes

    assert_includes channels_seen, :luminance
    assert_includes channels_seen, :chrominance
  end

  def test_quantization_modifier_rejects_nil_result
    error = assert_raises(ArgumentError) do
      PureJPEG.encode(@source, quantization_modifier: ->(_table, _channel) { nil }).to_bytes
    end

    assert_match(/quantization_modifier result/, error.message)
  end

  def test_quantization_modifier_rejects_malformed_result
    error = assert_raises(ArgumentError) do
      PureJPEG.encode(@source, quantization_modifier: ->(_table, _channel) { [1, 2, 3] }).to_bytes
    end

    assert_match(/must have exactly 64 elements/, error.message)
  end

  def test_all_creative_outputs_decodable
    encodings = [
      { quality: 20, scramble_quantization: true },
      { quality: 90, chroma_quality: 5 },
      { quality: 10, chroma_quality: 95 },
      { luminance_table: [1] + [255] * 63, chrominance_table: [1] + [255] * 63 },
    ]

    encodings.each do |opts|
      data = PureJPEG.encode(@source, **opts).to_bytes
      image = PureJPEG.read(data)
      assert_equal 64, image.width
      assert_equal 64, image.height
    end
  end
end
