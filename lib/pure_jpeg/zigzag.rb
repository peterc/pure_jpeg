# frozen_string_literal: true

module PureJPEG
  module Zigzag
    ORDER = [
       0,  1,  8, 16,  9,  2,  3, 10,
      17, 24, 32, 25, 18, 11,  4,  5,
      12, 19, 26, 33, 40, 48, 41, 34,
      27, 20, 13,  6,  7, 14, 21, 28,
      35, 42, 49, 56, 57, 50, 43, 36,
      29, 22, 15, 23, 30, 37, 44, 51,
      58, 59, 52, 45, 38, 31, 39, 46,
      53, 60, 61, 54, 47, 55, 62, 63
    ].freeze

    # Inverse order: INVERSE_ORDER[raster_pos] = zigzag_index
    # Used by unreorder! to convert via values_at instead of 64 individual stores.
    INVERSE_ORDER = Array.new(64).tap { |inv|
      ORDER.each_with_index { |raster_pos, zigzag_idx| inv[raster_pos] = zigzag_idx }
    }.freeze

    # Reorder an 8x8 block into zigzag order.
    # Uses Array#values_at (C-implemented bulk gather) instead of 64 individual
    # Ruby-level array accesses, which is ~3x faster under YJIT.
    def self.reorder!(block, _out = nil)
      block.values_at(*ORDER)
    end

    # Reverse zigzag: from zigzag order back to raster order.
    def self.unreorder!(zigzag, _out = nil)
      zigzag.values_at(*INVERSE_ORDER)
    end
  end
end
