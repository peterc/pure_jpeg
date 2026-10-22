# frozen_string_literal: true

require_relative "test_helper"
require "digest"

class TestAPICompatibility < Minitest::Test
  def test_encoder_bytes_match_040_across_options_and_sources
    # Reference digest captured using the unchanged v0.4.0 library. Exercise
    # all source layouts without needing ChunkyPNG at test runtime.
    raw = PureJPEG::Source::RawSource.new(19, 13) { |x, y| [x * 12, y * 19, (x + y) * 7] }
    rgb = 13.times.flat_map do |y|
      19.times.map { |x| (x * 12 << 16) | (y * 19 << 8) | (x + y) * 7 }
    end
    image = PureJPEG::Image.new(19, 13, rgb)
    png = Struct.new(:width, :height, :pixels).new(19, 13, rgb.map { |v| (v << 8) | 127 })
    sources = [raw, image, PureJPEG::Source::ChunkyPNGSource.new(png),
               PureJPEG::Source::ChunkyPNGSource.new(png, background: [40, 50, 60])]
    extras = [{}, { scramble_quantization: true },
              { luminance_table: Array.new(64, 15), chrominance_table: Array.new(64, 30) },
              { chroma_quality: 15 },
              { quantization_modifier: ->(table, _channel) { table.map { |v| [255, v + 2].min } } }]
    hashes = []
    sources.each do |source|
      [1, 50, 85, 95, 100].each do |quality|
        [false, true].each do |grayscale|
          [false, true].each do |optimize|
            extras.each do |options|
              bytes = PureJPEG.encode(source, quality: quality, grayscale: grayscale,
                                      optimize_huffman: optimize, **options).to_bytes
              hashes << Digest::SHA256.hexdigest(bytes)
            end
          end
        end
      end
    end
    assert_equal 400, hashes.length
    # Captured from unchanged v0.4.0 on each platform: macOS CRuby differs
    # from Linux CRuby and JRuby/TruffleRuby for some option combinations.
    # Preserve the platform's existing bytes, not another platform's output.
    expected = if RUBY_ENGINE == "ruby" && RUBY_PLATFORM.include?("darwin")
                 "f7f2232ee301eb1158632af6c2168087e85f0b81054f80d8b6d816f321956ea2"
               else
                 "9b556ce569cb8dd6daa9282c3675e72bedafd20ebcb54b66a67f6c1543105ebb"
               end
    assert_equal expected, Digest::SHA256.hexdigest(hashes.join)
  end

  def test_scan_struct_retains_positional_contract
    members = [:components, :spectral_start, :spectral_end, :successive_high,
               :successive_low, :data, :huffman_tables]
    assert_equal members, PureJPEG::JFIFReader::Scan.members
    values = [[], 0, 63, 0, 0, "data", {}]
    scan = PureJPEG::JFIFReader::Scan.new(*values)
    assert_equal values, scan.to_a
  end
end
