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
    INVERSE_ORDER = Array.new(64).tap { |inv|
      ORDER.each_with_index { |raster_pos, zigzag_idx| inv[raster_pos] = zigzag_idx }
    }.freeze

    # Reorder an 8x8 block from raster order into zigzag order.
    # Writes into pre-allocated `out` buffer to avoid allocating a new Array.
    # Uses a while loop instead of 64 unrolled assignments — YJIT generates
    # a single compact block (~2KB) vs 320 blocks (~100KB) for unrolled code,
    # dramatically reducing L1 I-cache pressure on Apple Silicon (192KB L1i).
    def self.reorder!(block, out)
      i = 0
      while i < 64
        out[i] = block[ORDER[i]]
        i += 1
      end
      out
    end

    # Reverse zigzag: from zigzag order back to raster order.
    # Writes into pre-allocated `out` buffer to avoid allocating a new Array.
    def self.unreorder!(zigzag, out)
      i = 0
      while i < 64
        out[i] = zigzag[INVERSE_ORDER[i]]
        i += 1
      end
      out
    end
  end
end
