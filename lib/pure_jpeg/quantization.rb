# frozen_string_literal: true

module PureJPEG
  module Quantization
    # Standard luminance quantization table (JPEG Annex K, Table K.1)
    LUMINANCE_BASE = [
      16, 11, 10, 16,  24,  40,  51,  61,
      12, 12, 14, 19,  26,  58,  60,  55,
      14, 13, 16, 24,  40,  57,  69,  56,
      14, 17, 22, 29,  51,  87,  80,  62,
      18, 22, 37, 56,  68, 109, 103,  77,
      24, 35, 55, 64,  81, 104, 113,  92,
      49, 64, 78, 87, 103, 121, 120, 101,
      72, 92, 95, 98, 112, 100, 103,  99
    ].freeze

    # Standard chrominance quantization table (JPEG Annex K, Table K.2)
    CHROMINANCE_BASE = [
      17, 18, 24, 47, 99, 99, 99, 99,
      18, 21, 26, 66, 99, 99, 99, 99,
      24, 26, 56, 99, 99, 99, 99, 99,
      47, 66, 99, 99, 99, 99, 99, 99,
      99, 99, 99, 99, 99, 99, 99, 99,
      99, 99, 99, 99, 99, 99, 99, 99,
      99, 99, 99, 99, 99, 99, 99, 99,
      99, 99, 99, 99, 99, 99, 99, 99
    ].freeze

    # Scale a base quantization table for a given quality (1-100).
    def self.scale_table(base, quality)
      quality = quality.clamp(1, 100)
      scale = quality < 50 ? 5000.0 / quality : 200.0 - 2.0 * quality

      base.map { |v|
        ((v * scale + 50.0) / 100.0).round.clamp(1, 255)
      }
    end

    # Quantize a 64-element DCT block into `out`.
    # Uses integer rounding division (round-to-nearest) to match the
    # behavior of Float division + round from the previous float DCT.
    def self.quantize!(block, table, out)
      i = 0
      while i < 64
        v = block[i]; t = table[i]
        out[i] = if v >= 0
                   (v + (t >> 1)) / t
                 else
                   -((-v + (t >> 1)) / t)
                 end
        i += 1
      end
      out
    end

    # Dequantize: multiply each coefficient by its quantization table entry.
    def self.dequantize!(block, table, out)
      i = 0
      while i < 64
        out[i] = block[i] * table[i]
        i += 1
      end
      out
    end
  end
end
