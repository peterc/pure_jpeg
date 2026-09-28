# frozen_string_literal: true

require_relative "test_helper"

class TestChromaDownsampling < Minitest::Test
  def test_odd_edges_and_per_pixel_chroma_clamping
    # Includes saturated colors whose chroma rounds to 256 before clamping.
    pixels = [0xff0000, 0x00ff00, 0x0000ff,
              0xffffff, 0x000000, 0x808080,
              0xffff00, 0x00ffff, 0xff00ff]
    expected = [[76, 150, 29, 255, 0, 128, 226, 179, 105],
                [96, 191, 86, 212], [133, 117, 75, 235]]
    packed = PureJPEG::Image.new(3, 3, pixels)
    raw = PureJPEG::Source::RawSource.new(3, 3) do |x, y|
      color = pixels[y * 3 + x]
      [color >> 16, (color >> 8) & 255, color & 255]
    end

    [packed, raw].each do |source|
      assert_equal expected, PureJPEG.encode(source).send(:extract_ycbcr420, 3, 3)
    end
  end

  def test_single_pixel_replicates_both_edges
    source = PureJPEG::Image.new(1, 1, [0x0000ff])
    assert_equal [[29], [255], [107]], PureJPEG.encode(source).send(:extract_ycbcr420, 1, 1)
  end

  def test_source_is_read_once_per_pixel_in_raster_order
    coordinates = []
    source = Object.new
    source.define_singleton_method(:width) { 3 }
    source.define_singleton_method(:height) { 5 }
    source.define_singleton_method(:[]) do |x, y|
      coordinates << [x, y]
      PureJPEG::Source::Pixel.new(128, 128, 128)
    end

    data = PureJPEG.encode(source, optimize_huffman: true).to_bytes
    assert_equal (0...5).flat_map { |y| (0...3).map { |x| [x, y] } }, coordinates
    assert_equal [0x808080] * 15, PureJPEG.read(data).packed_pixels
  end
end
