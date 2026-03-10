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

    # Separable forward 2D DCT: row pass then column pass.
    # Writes result into `out`. Uses `temp` as scratch space.
    # All three arrays must be pre-allocated with 64 elements.
    def self.forward!(block, temp, out)
      # Row pass: temp[y*8+u] = sum_x A[u][x] * block[y*8+x]
      m = MATRIX_FLAT
      y = 0
      while y < 8
        y8 = y << 3
        b0 = block[y8]; b1 = block[y8|1]; b2 = block[y8|2]; b3 = block[y8|3]
        b4 = block[y8|4]; b5 = block[y8|5]; b6 = block[y8|6]; b7 = block[y8|7]
        u = 0
        while u < 8
          u8 = u << 3
          temp[y8|u] = m[u8]*b0 + m[u8|1]*b1 + m[u8|2]*b2 + m[u8|3]*b3 +
                       m[u8|4]*b4 + m[u8|5]*b5 + m[u8|6]*b6 + m[u8|7]*b7
          u += 1
        end
        y += 1
      end

      # Column pass: out[v*8+u] = sum_y A[v][y] * temp[y*8+u]
      u = 0
      while u < 8
        t0 = temp[u]; t1 = temp[8|u]; t2 = temp[16|u]; t3 = temp[24|u]
        t4 = temp[32|u]; t5 = temp[40|u]; t6 = temp[48|u]; t7 = temp[56|u]
        v = 0
        while v < 8
          v8 = v << 3
          out[v8|u] = m[v8]*t0 + m[v8|1]*t1 + m[v8|2]*t2 + m[v8|3]*t3 +
                      m[v8|4]*t4 + m[v8|5]*t5 + m[v8|6]*t6 + m[v8|7]*t7
          v += 1
        end
        u += 1
      end

      out
    end

    # Separable inverse 2D DCT: same structure as forward but using A^T.
    # f = A^T * F * A
    def self.inverse!(block, temp, out)
      mt = MATRIX_T_FLAT

      # Row pass: temp[v*8+x] = sum_u A^T[x][u] * block[v*8+u]
      v = 0
      while v < 8
        v8 = v << 3
        b0 = block[v8]; b1 = block[v8|1]; b2 = block[v8|2]; b3 = block[v8|3]
        b4 = block[v8|4]; b5 = block[v8|5]; b6 = block[v8|6]; b7 = block[v8|7]
        x = 0
        while x < 8
          x8 = x << 3
          temp[v8|x] = mt[x8]*b0 + mt[x8|1]*b1 + mt[x8|2]*b2 + mt[x8|3]*b3 +
                        mt[x8|4]*b4 + mt[x8|5]*b5 + mt[x8|6]*b6 + mt[x8|7]*b7
          x += 1
        end
        v += 1
      end

      # Column pass: out[y*8+x] = sum_v A^T[y][v] * temp[v*8+x]
      x = 0
      while x < 8
        t0 = temp[x]; t1 = temp[8|x]; t2 = temp[16|x]; t3 = temp[24|x]
        t4 = temp[32|x]; t5 = temp[40|x]; t6 = temp[48|x]; t7 = temp[56|x]
        y = 0
        while y < 8
          y8 = y << 3
          out[y8|x] = mt[y8]*t0 + mt[y8|1]*t1 + mt[y8|2]*t2 + mt[y8|3]*t3 +
                       mt[y8|4]*t4 + mt[y8|5]*t5 + mt[y8|6]*t6 + mt[y8|7]*t7
          y += 1
        end
        x += 1
      end

      out
    end
  end
end
