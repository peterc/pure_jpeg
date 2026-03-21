# frozen_string_literal: true

module PureJPEG
  module DCT
    # Precomputed 8x8 DCT matrix: A[k][n] = (C(k)/2) * cos((2n+1)*k*pi/16)
    # where C(0) = 1/sqrt(2), C(k) = 1 for k > 0.
    # This lets us do the 2D DCT as two 1D matrix-vector multiplies (separable).
    MATRIX = Array.new(8) { |k|
      ck = k == 0 ? 0.5 / Math.sqrt(2.0) : 0.5
      Array.new(8) { |n|
        ck * Math.cos((2.0 * n + 1.0) * k * Math::PI / 16.0)
      }
    }.freeze

    # Flatten for faster indexed access
    MATRIX_FLAT = MATRIX.flatten.freeze

    # Transposed matrix for inverse DCT: A^T[n][k] = A[k][n]
    MATRIX_T_FLAT = Array.new(64) { |i| MATRIX_FLAT[(i % 8) * 8 + i / 8] }.freeze

    # Separable forward 2D DCT with inner loops unrolled.
    # Writes result into `out`. Uses `temp` as scratch space.
    # All three arrays must be pre-allocated with 64 elements.
    def self.forward!(block, temp, out)
      m = MATRIX_FLAT

      # Row pass: temp[y*8+u] = sum_x M[u*8+x] * block[y*8+x]
      8.times do |y|
        y8 = y << 3
        b0 = block[y8]; b1 = block[y8|1]; b2 = block[y8|2]; b3 = block[y8|3]
        b4 = block[y8|4]; b5 = block[y8|5]; b6 = block[y8|6]; b7 = block[y8|7]
        temp[y8|0] = m[0]*b0 + m[1]*b1 + m[2]*b2 + m[3]*b3 + m[4]*b4 + m[5]*b5 + m[6]*b6 + m[7]*b7
        temp[y8|1] = m[8]*b0 + m[9]*b1 + m[10]*b2 + m[11]*b3 + m[12]*b4 + m[13]*b5 + m[14]*b6 + m[15]*b7
        temp[y8|2] = m[16]*b0 + m[17]*b1 + m[18]*b2 + m[19]*b3 + m[20]*b4 + m[21]*b5 + m[22]*b6 + m[23]*b7
        temp[y8|3] = m[24]*b0 + m[25]*b1 + m[26]*b2 + m[27]*b3 + m[28]*b4 + m[29]*b5 + m[30]*b6 + m[31]*b7
        temp[y8|4] = m[32]*b0 + m[33]*b1 + m[34]*b2 + m[35]*b3 + m[36]*b4 + m[37]*b5 + m[38]*b6 + m[39]*b7
        temp[y8|5] = m[40]*b0 + m[41]*b1 + m[42]*b2 + m[43]*b3 + m[44]*b4 + m[45]*b5 + m[46]*b6 + m[47]*b7
        temp[y8|6] = m[48]*b0 + m[49]*b1 + m[50]*b2 + m[51]*b3 + m[52]*b4 + m[53]*b5 + m[54]*b6 + m[55]*b7
        temp[y8|7] = m[56]*b0 + m[57]*b1 + m[58]*b2 + m[59]*b3 + m[60]*b4 + m[61]*b5 + m[62]*b6 + m[63]*b7
      end

      # Column pass: out[v*8+u] = sum_y M[v*8+y] * temp[y*8+u]
      8.times do |u|
        t0 = temp[u]; t1 = temp[8|u]; t2 = temp[16|u]; t3 = temp[24|u]
        t4 = temp[32|u]; t5 = temp[40|u]; t6 = temp[48|u]; t7 = temp[56|u]
        out[0|u] = m[0]*t0 + m[1]*t1 + m[2]*t2 + m[3]*t3 + m[4]*t4 + m[5]*t5 + m[6]*t6 + m[7]*t7
        out[8|u] = m[8]*t0 + m[9]*t1 + m[10]*t2 + m[11]*t3 + m[12]*t4 + m[13]*t5 + m[14]*t6 + m[15]*t7
        out[16|u] = m[16]*t0 + m[17]*t1 + m[18]*t2 + m[19]*t3 + m[20]*t4 + m[21]*t5 + m[22]*t6 + m[23]*t7
        out[24|u] = m[24]*t0 + m[25]*t1 + m[26]*t2 + m[27]*t3 + m[28]*t4 + m[29]*t5 + m[30]*t6 + m[31]*t7
        out[32|u] = m[32]*t0 + m[33]*t1 + m[34]*t2 + m[35]*t3 + m[36]*t4 + m[37]*t5 + m[38]*t6 + m[39]*t7
        out[40|u] = m[40]*t0 + m[41]*t1 + m[42]*t2 + m[43]*t3 + m[44]*t4 + m[45]*t5 + m[46]*t6 + m[47]*t7
        out[48|u] = m[48]*t0 + m[49]*t1 + m[50]*t2 + m[51]*t3 + m[52]*t4 + m[53]*t5 + m[54]*t6 + m[55]*t7
        out[56|u] = m[56]*t0 + m[57]*t1 + m[58]*t2 + m[59]*t3 + m[60]*t4 + m[61]*t5 + m[62]*t6 + m[63]*t7
      end

      out
    end

    # Separable inverse 2D DCT with inner loops unrolled.
    def self.inverse!(block, temp, out)
      mt = MATRIX_T_FLAT

      # Row pass
      8.times do |v|
        v8 = v << 3
        b0 = block[v8]; b1 = block[v8|1]; b2 = block[v8|2]; b3 = block[v8|3]
        b4 = block[v8|4]; b5 = block[v8|5]; b6 = block[v8|6]; b7 = block[v8|7]
        temp[v8|0] = mt[0]*b0 + mt[1]*b1 + mt[2]*b2 + mt[3]*b3 + mt[4]*b4 + mt[5]*b5 + mt[6]*b6 + mt[7]*b7
        temp[v8|1] = mt[8]*b0 + mt[9]*b1 + mt[10]*b2 + mt[11]*b3 + mt[12]*b4 + mt[13]*b5 + mt[14]*b6 + mt[15]*b7
        temp[v8|2] = mt[16]*b0 + mt[17]*b1 + mt[18]*b2 + mt[19]*b3 + mt[20]*b4 + mt[21]*b5 + mt[22]*b6 + mt[23]*b7
        temp[v8|3] = mt[24]*b0 + mt[25]*b1 + mt[26]*b2 + mt[27]*b3 + mt[28]*b4 + mt[29]*b5 + mt[30]*b6 + mt[31]*b7
        temp[v8|4] = mt[32]*b0 + mt[33]*b1 + mt[34]*b2 + mt[35]*b3 + mt[36]*b4 + mt[37]*b5 + mt[38]*b6 + mt[39]*b7
        temp[v8|5] = mt[40]*b0 + mt[41]*b1 + mt[42]*b2 + mt[43]*b3 + mt[44]*b4 + mt[45]*b5 + mt[46]*b6 + mt[47]*b7
        temp[v8|6] = mt[48]*b0 + mt[49]*b1 + mt[50]*b2 + mt[51]*b3 + mt[52]*b4 + mt[53]*b5 + mt[54]*b6 + mt[55]*b7
        temp[v8|7] = mt[56]*b0 + mt[57]*b1 + mt[58]*b2 + mt[59]*b3 + mt[60]*b4 + mt[61]*b5 + mt[62]*b6 + mt[63]*b7
      end

      # Column pass
      8.times do |x|
        t0 = temp[x]; t1 = temp[8|x]; t2 = temp[16|x]; t3 = temp[24|x]
        t4 = temp[32|x]; t5 = temp[40|x]; t6 = temp[48|x]; t7 = temp[56|x]
        out[0|x] = mt[0]*t0 + mt[1]*t1 + mt[2]*t2 + mt[3]*t3 + mt[4]*t4 + mt[5]*t5 + mt[6]*t6 + mt[7]*t7
        out[8|x] = mt[8]*t0 + mt[9]*t1 + mt[10]*t2 + mt[11]*t3 + mt[12]*t4 + mt[13]*t5 + mt[14]*t6 + mt[15]*t7
        out[16|x] = mt[16]*t0 + mt[17]*t1 + mt[18]*t2 + mt[19]*t3 + mt[20]*t4 + mt[21]*t5 + mt[22]*t6 + mt[23]*t7
        out[24|x] = mt[24]*t0 + mt[25]*t1 + mt[26]*t2 + mt[27]*t3 + mt[28]*t4 + mt[29]*t5 + mt[30]*t6 + mt[31]*t7
        out[32|x] = mt[32]*t0 + mt[33]*t1 + mt[34]*t2 + mt[35]*t3 + mt[36]*t4 + mt[37]*t5 + mt[38]*t6 + mt[39]*t7
        out[40|x] = mt[40]*t0 + mt[41]*t1 + mt[42]*t2 + mt[43]*t3 + mt[44]*t4 + mt[45]*t5 + mt[46]*t6 + mt[47]*t7
        out[48|x] = mt[48]*t0 + mt[49]*t1 + mt[50]*t2 + mt[51]*t3 + mt[52]*t4 + mt[53]*t5 + mt[54]*t6 + mt[55]*t7
        out[56|x] = mt[56]*t0 + mt[57]*t1 + mt[58]*t2 + mt[59]*t3 + mt[60]*t4 + mt[61]*t5 + mt[62]*t6 + mt[63]*t7
      end

      out
    end
  end
end
