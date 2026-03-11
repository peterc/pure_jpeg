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

    # Reorder an 8x8 block into zigzag order, writing into `out`.
    def self.reorder!(block, out)
      64.times { |i| out[i] = block[ORDER[i]] }
      out
    end

    # Reverse zigzag: from zigzag order back to raster order.
    def self.unreorder!(zigzag, out)
      64.times { |i| out[ORDER[i]] = zigzag[i] }
      out
    end
  end
end
