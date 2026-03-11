# frozen_string_literal: true

module PureJPEG
  # Integer-scaled DCT based on the IJG (Independent JPEG Group) reference
  # implementation (jfdctint.c / jidctint.c). Uses the Arai-Agui-Nakajima
  # factorization with 13-bit fixed-point constants.
  #
  # All arithmetic is pure Integer (additions, shifts, multiplies) — no Float
  # operations. This is ~3x faster than the matrix-multiply float DCT under
  # YJIT and eliminates millions of Float object allocations during decode.
  module DCT
    # Keep the float matrix available for reference / testing
    MATRIX = Array.new(8) { |k|
      ck = k == 0 ? 0.5 / Math.sqrt(2.0) : 0.5
      Array.new(8) { |n|
        ck * Math.cos((2.0 * n + 1.0) * k * Math::PI / 16.0)
      }
    }.freeze

    MATRIX_FLAT = MATRIX.flatten.freeze
    MATRIX_T_FLAT = Array.new(64) { |i| MATRIX_FLAT[(i % 8) * 8 + i / 8] }.freeze

    # Fixed-point constants (13-bit precision) from IJG reference.
    CONST_BITS = 13
    PASS1_BITS = 2

    FIX_0_298631336 = 2446
    FIX_0_390180644 = 3196
    FIX_0_541196100 = 4433
    FIX_0_765366865 = 6270
    FIX_0_899976223 = 7373
    FIX_1_175875602 = 9633
    FIX_1_501321110 = 12299
    FIX_1_847759065 = 15137
    FIX_1_961570560 = 16069
    FIX_2_053119869 = 16819
    FIX_2_562915447 = 20995
    FIX_3_072711026 = 25172

    CB = CONST_BITS
    P1 = PASS1_BITS
    CB_M_P1 = CB - P1        # 11
    CB_P_P1_P3 = CB + P1 + 3 # 18
    P1_P3 = P1 + 3           # 5

    # Precomputed rounding biases — avoids runtime (1 << (X - 1)) computation.
    # YJIT disasm showed each use generates 3-4 bytecodes for constant lookup,
    # subtract, and shift; precomputing eliminates ~40 bytecodes per DCT call.
    ROUND_CB_M_P1     = 1 << (CB_M_P1 - 1)       # 1024
    ROUND_CB_P_P1_P3  = 1 << (CB_P_P1_P3 - 1)    # 131072
    ROUND_P1_P3       = 1 << (P1_P3 - 1)          # 16

    # Precomputed negative constants — avoids runtime unary-minus (-@) calls.
    # YJIT disasm showed each `-CONST` generates an extra `opt_send_without_block -@`
    # instruction that calls into C; precomputing saves ~8 C calls per pass.
    NEG_FIX_0_899976223 = -FIX_0_899976223
    NEG_FIX_2_562915447 = -FIX_2_562915447
    NEG_FIX_1_961570560 = -FIX_1_961570560
    NEG_FIX_0_390180644 = -FIX_0_390180644

    # Forward 2D DCT (in-place). Input: 64-element array of level-shifted
    # integers (-128..127). Output: DCT coefficients (integers).
    # The `_temp` and `_out` parameters are accepted for API compatibility
    # but ignored; computation is done in-place on `data`.
    def self.forward!(data, _temp = nil, _out = nil)
      # Pass 1: process rows
      8.times do |row|
        i = row << 3
        d0 = data[i]; d1 = data[i+1]; d2 = data[i+2]; d3 = data[i+3]
        d4 = data[i+4]; d5 = data[i+5]; d6 = data[i+6]; d7 = data[i+7]

        tmp0 = d0 + d7; tmp7 = d0 - d7
        tmp1 = d1 + d6; tmp6 = d1 - d6
        tmp2 = d2 + d5; tmp5 = d2 - d5
        tmp3 = d3 + d4; tmp4 = d3 - d4

        # Even part
        tmp10 = tmp0 + tmp3; tmp13 = tmp0 - tmp3
        tmp11 = tmp1 + tmp2; tmp12 = tmp1 - tmp2

        data[i]   = (tmp10 + tmp11) << P1
        data[i+4] = (tmp10 - tmp11) << P1

        z1 = (tmp12 + tmp13) * FIX_0_541196100
        data[i+2] = (z1 + tmp13 * FIX_0_765366865 + ROUND_CB_M_P1) >> CB_M_P1
        data[i+6] = (z1 - tmp12 * FIX_1_847759065 + ROUND_CB_M_P1) >> CB_M_P1

        # Odd part
        z1 = tmp4 + tmp7; z2 = tmp5 + tmp6
        z3 = tmp4 + tmp6; z4 = tmp5 + tmp7
        z5 = (z3 + z4) * FIX_1_175875602

        tmp4 = tmp4 * FIX_0_298631336
        tmp5 = tmp5 * FIX_2_053119869
        tmp6 = tmp6 * FIX_3_072711026
        tmp7 = tmp7 * FIX_1_501321110
        z1 = z1 * NEG_FIX_0_899976223
        z2 = z2 * NEG_FIX_2_562915447
        z3 = z3 * NEG_FIX_1_961570560 + z5
        z4 = z4 * NEG_FIX_0_390180644 + z5

        data[i+7] = (tmp4 + z1 + z3 + ROUND_CB_M_P1) >> CB_M_P1
        data[i+5] = (tmp5 + z2 + z4 + ROUND_CB_M_P1) >> CB_M_P1
        data[i+3] = (tmp6 + z2 + z3 + ROUND_CB_M_P1) >> CB_M_P1
        data[i+1] = (tmp7 + z1 + z4 + ROUND_CB_M_P1) >> CB_M_P1
      end

      # Pass 2: process columns
      8.times do |col|
        d0 = data[col]; d1 = data[col+8]; d2 = data[col+16]; d3 = data[col+24]
        d4 = data[col+32]; d5 = data[col+40]; d6 = data[col+48]; d7 = data[col+56]

        tmp0 = d0 + d7; tmp7 = d0 - d7
        tmp1 = d1 + d6; tmp6 = d1 - d6
        tmp2 = d2 + d5; tmp5 = d2 - d5
        tmp3 = d3 + d4; tmp4 = d3 - d4

        tmp10 = tmp0 + tmp3; tmp13 = tmp0 - tmp3
        tmp11 = tmp1 + tmp2; tmp12 = tmp1 - tmp2

        data[col]    = (tmp10 + tmp11 + ROUND_P1_P3) >> P1_P3
        data[col+32] = (tmp10 - tmp11 + ROUND_P1_P3) >> P1_P3

        z1 = (tmp12 + tmp13) * FIX_0_541196100
        data[col+16] = (z1 + tmp13 * FIX_0_765366865 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[col+48] = (z1 - tmp12 * FIX_1_847759065 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3

        z1 = tmp4 + tmp7; z2 = tmp5 + tmp6
        z3 = tmp4 + tmp6; z4 = tmp5 + tmp7
        z5 = (z3 + z4) * FIX_1_175875602

        tmp4 = tmp4 * FIX_0_298631336
        tmp5 = tmp5 * FIX_2_053119869
        tmp6 = tmp6 * FIX_3_072711026
        tmp7 = tmp7 * FIX_1_501321110
        z1 = z1 * NEG_FIX_0_899976223
        z2 = z2 * NEG_FIX_2_562915447
        z3 = z3 * NEG_FIX_1_961570560 + z5
        z4 = z4 * NEG_FIX_0_390180644 + z5

        data[col+56] = (tmp4 + z1 + z3 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[col+40] = (tmp5 + z2 + z4 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[col+24] = (tmp6 + z2 + z3 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[col+8]  = (tmp7 + z1 + z4 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
      end

      data
    end

    # Inverse 2D DCT (in-place). Input: dequantized DCT coefficients (integers).
    # Output: spatial-domain values (integers) that still need +128 level shift.
    def self.inverse!(data, _temp = nil, _out = nil)
      # Pass 1: process columns
      8.times do |col|
        d0 = data[col]; d2 = data[col+16]; d4 = data[col+32]; d6 = data[col+48]
        d1 = data[col+8]; d3 = data[col+24]; d5 = data[col+40]; d7 = data[col+56]

        # Even part
        z1 = (d2 + d6) * FIX_0_541196100
        tmp2 = z1 - d6 * FIX_1_847759065
        tmp3 = z1 + d2 * FIX_0_765366865

        tmp0 = (d0 + d4) << CB
        tmp1 = (d0 - d4) << CB

        tmp10 = tmp0 + tmp3; tmp13 = tmp0 - tmp3
        tmp11 = tmp1 + tmp2; tmp12 = tmp1 - tmp2

        # Odd part
        tmp0 = d7; tmp1 = d5; tmp2 = d3; tmp3 = d1
        z1 = tmp0 + tmp3; z2 = tmp1 + tmp2
        z3 = tmp0 + tmp2; z4 = tmp1 + tmp3
        z5 = (z3 + z4) * FIX_1_175875602

        tmp0 = tmp0 * FIX_0_298631336
        tmp1 = tmp1 * FIX_2_053119869
        tmp2 = tmp2 * FIX_3_072711026
        tmp3 = tmp3 * FIX_1_501321110
        z1 = z1 * NEG_FIX_0_899976223
        z2 = z2 * NEG_FIX_2_562915447
        z3 = z3 * NEG_FIX_1_961570560 + z5
        z4 = z4 * NEG_FIX_0_390180644 + z5

        tmp0 += z1 + z3; tmp1 += z2 + z4
        tmp2 += z2 + z3; tmp3 += z1 + z4

        data[col]    = (tmp10 + tmp3 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+56] = (tmp10 - tmp3 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+8]  = (tmp11 + tmp2 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+48] = (tmp11 - tmp2 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+16] = (tmp12 + tmp1 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+40] = (tmp12 - tmp1 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+24] = (tmp13 + tmp0 + ROUND_CB_M_P1) >> CB_M_P1
        data[col+32] = (tmp13 - tmp0 + ROUND_CB_M_P1) >> CB_M_P1
      end

      # Pass 2: process rows
      8.times do |row|
        i = row << 3
        d0 = data[i]; d2 = data[i+2]; d4 = data[i+4]; d6 = data[i+6]
        d1 = data[i+1]; d3 = data[i+3]; d5 = data[i+5]; d7 = data[i+7]

        # Even part
        z1 = (d2 + d6) * FIX_0_541196100
        tmp2 = z1 - d6 * FIX_1_847759065
        tmp3 = z1 + d2 * FIX_0_765366865

        tmp0 = (d0 + d4) << CB
        tmp1 = (d0 - d4) << CB

        tmp10 = tmp0 + tmp3; tmp13 = tmp0 - tmp3
        tmp11 = tmp1 + tmp2; tmp12 = tmp1 - tmp2

        # Odd part
        tmp0 = d7; tmp1 = d5; tmp2 = d3; tmp3 = d1
        z1 = tmp0 + tmp3; z2 = tmp1 + tmp2
        z3 = tmp0 + tmp2; z4 = tmp1 + tmp3
        z5 = (z3 + z4) * FIX_1_175875602

        tmp0 = tmp0 * FIX_0_298631336
        tmp1 = tmp1 * FIX_2_053119869
        tmp2 = tmp2 * FIX_3_072711026
        tmp3 = tmp3 * FIX_1_501321110
        z1 = z1 * NEG_FIX_0_899976223
        z2 = z2 * NEG_FIX_2_562915447
        z3 = z3 * NEG_FIX_1_961570560 + z5
        z4 = z4 * NEG_FIX_0_390180644 + z5

        tmp0 += z1 + z3; tmp1 += z2 + z4
        tmp2 += z2 + z3; tmp3 += z1 + z4

        data[i]   = (tmp10 + tmp3 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+7] = (tmp10 - tmp3 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+1] = (tmp11 + tmp2 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+6] = (tmp11 - tmp2 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+2] = (tmp12 + tmp1 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+5] = (tmp12 - tmp1 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+3] = (tmp13 + tmp0 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
        data[i+4] = (tmp13 - tmp0 + ROUND_CB_P_P1_P3) >> CB_P_P1_P3
      end

      data
    end
  end
end
