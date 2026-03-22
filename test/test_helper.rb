# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start
rescue LoadError
  # simplecov not available
end

require "minitest/autorun"
require_relative "../lib/pure_jpeg"

module TestHelper
  def gradient_source(width = 64, height = 64)
    PureJPEG::Source::RawSource.new(width, height) do |x, y|
      r = width > 1 ? ((x / (width - 1).to_f) * 255).round : 128
      g = height > 1 ? ((y / (height - 1).to_f) * 255).round : 128
      b = (width + height > 2) ? (((x + y) / (width + height - 2).to_f) * 255).round : 128
      [r, g, b]
    end
  end

  def assert_valid_pixel(pixel)
    assert_respond_to pixel, :r
    assert_respond_to pixel, :g
    assert_respond_to pixel, :b
    assert_includes 0..255, pixel.r
    assert_includes 0..255, pixel.g
    assert_includes 0..255, pixel.b
  end
end
