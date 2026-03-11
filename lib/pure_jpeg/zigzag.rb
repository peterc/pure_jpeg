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
    # out[i] = block[ORDER[i]] for i in 0..63
    def self.reorder!(block, out)
      out[ 0] = block[ 0]; out[ 1] = block[ 1]; out[ 2] = block[ 8]; out[ 3] = block[16]
      out[ 4] = block[ 9]; out[ 5] = block[ 2]; out[ 6] = block[ 3]; out[ 7] = block[10]
      out[ 8] = block[17]; out[ 9] = block[24]; out[10] = block[32]; out[11] = block[25]
      out[12] = block[18]; out[13] = block[11]; out[14] = block[ 4]; out[15] = block[ 5]
      out[16] = block[12]; out[17] = block[19]; out[18] = block[26]; out[19] = block[33]
      out[20] = block[40]; out[21] = block[48]; out[22] = block[41]; out[23] = block[34]
      out[24] = block[27]; out[25] = block[20]; out[26] = block[13]; out[27] = block[ 6]
      out[28] = block[ 7]; out[29] = block[14]; out[30] = block[21]; out[31] = block[28]
      out[32] = block[35]; out[33] = block[42]; out[34] = block[49]; out[35] = block[56]
      out[36] = block[57]; out[37] = block[50]; out[38] = block[43]; out[39] = block[36]
      out[40] = block[29]; out[41] = block[22]; out[42] = block[15]; out[43] = block[23]
      out[44] = block[30]; out[45] = block[37]; out[46] = block[44]; out[47] = block[51]
      out[48] = block[58]; out[49] = block[59]; out[50] = block[52]; out[51] = block[45]
      out[52] = block[38]; out[53] = block[31]; out[54] = block[39]; out[55] = block[46]
      out[56] = block[53]; out[57] = block[60]; out[58] = block[61]; out[59] = block[54]
      out[60] = block[47]; out[61] = block[55]; out[62] = block[62]; out[63] = block[63]
      out
    end

    # Reverse zigzag: from zigzag order back to raster order.
    # Writes into pre-allocated `out` buffer to avoid allocating a new Array.
    # out[ORDER[i]] = zigzag[i] for i in 0..63
    # Equivalently: out[raster_pos] = zigzag[INVERSE_ORDER[raster_pos]]
    def self.unreorder!(zigzag, out)
      out[ 0] = zigzag[ 0]; out[ 1] = zigzag[ 1]; out[ 2] = zigzag[ 5]; out[ 3] = zigzag[ 6]
      out[ 4] = zigzag[14]; out[ 5] = zigzag[15]; out[ 6] = zigzag[27]; out[ 7] = zigzag[28]
      out[ 8] = zigzag[ 2]; out[ 9] = zigzag[ 4]; out[10] = zigzag[ 7]; out[11] = zigzag[13]
      out[12] = zigzag[16]; out[13] = zigzag[26]; out[14] = zigzag[29]; out[15] = zigzag[42]
      out[16] = zigzag[ 3]; out[17] = zigzag[ 8]; out[18] = zigzag[12]; out[19] = zigzag[17]
      out[20] = zigzag[25]; out[21] = zigzag[30]; out[22] = zigzag[41]; out[23] = zigzag[43]
      out[24] = zigzag[ 9]; out[25] = zigzag[11]; out[26] = zigzag[18]; out[27] = zigzag[24]
      out[28] = zigzag[31]; out[29] = zigzag[40]; out[30] = zigzag[44]; out[31] = zigzag[53]
      out[32] = zigzag[10]; out[33] = zigzag[19]; out[34] = zigzag[23]; out[35] = zigzag[32]
      out[36] = zigzag[39]; out[37] = zigzag[45]; out[38] = zigzag[52]; out[39] = zigzag[54]
      out[40] = zigzag[20]; out[41] = zigzag[22]; out[42] = zigzag[33]; out[43] = zigzag[38]
      out[44] = zigzag[46]; out[45] = zigzag[51]; out[46] = zigzag[55]; out[47] = zigzag[60]
      out[48] = zigzag[21]; out[49] = zigzag[34]; out[50] = zigzag[37]; out[51] = zigzag[47]
      out[52] = zigzag[50]; out[53] = zigzag[56]; out[54] = zigzag[59]; out[55] = zigzag[61]
      out[56] = zigzag[35]; out[57] = zigzag[36]; out[58] = zigzag[48]; out[59] = zigzag[49]
      out[60] = zigzag[57]; out[61] = zigzag[58]; out[62] = zigzag[62]; out[63] = zigzag[63]
      out
    end
  end
end
