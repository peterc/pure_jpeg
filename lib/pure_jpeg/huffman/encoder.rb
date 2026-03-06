# frozen_string_literal: true

module PureJPEG
  module Huffman
    class Encoder
      def initialize(dc_table, ac_table)
        @dc_table = dc_table
        @ac_table = ac_table
      end

      # Encode a single 8x8 block (in zigzag order, quantized).
      # `prev_dc` is the DC value of the previous block (for DPCM).
      # Writes encoded bits to `writer` (a BitWriter).
      # Returns the current block's DC value.
      def encode_block(zigzag, prev_dc, writer)
        dc = zigzag[0]
        diff = dc - prev_dc
        encode_dc(diff, writer)
        encode_ac(zigzag, writer)
        dc
      end

      private

      def encode_dc(diff, writer)
        cat, bits = category_and_bits(diff)
        code, length = @dc_table[cat]
        writer.write_bits(code, length)
        writer.write_bits(bits, cat) if cat > 0
      end

      def encode_ac(zigzag, writer)
        last_nonzero = 63
        last_nonzero -= 1 while last_nonzero > 0 && zigzag[last_nonzero] == 0

        if last_nonzero == 0
          # All AC coefficients are zero (AC starts at index 1)
          eob = @ac_table[0x00]
          writer.write_bits(eob[0], eob[1])
          return
        end

        i = 1
        while i <= last_nonzero
          run = 0
          while i <= last_nonzero && zigzag[i] == 0
            run += 1
            i += 1
          end

          # Emit ZRL (16 zeros) symbols as needed
          while run >= 16
            zrl = @ac_table[0xF0]
            writer.write_bits(zrl[0], zrl[1])
            run -= 16
          end

          cat, bits = category_and_bits(zigzag[i])
          symbol = (run << 4) | cat
          code, length = @ac_table[symbol]
          writer.write_bits(code, length)
          writer.write_bits(bits, cat) if cat > 0
          i += 1
        end

        # EOB if we didn't reach position 63
        if last_nonzero < 63
          eob = @ac_table[0x00]
          writer.write_bits(eob[0], eob[1])
        end
      end

      # Returns [category, encoded_bits] for a coefficient value.
      def category_and_bits(value)
        return [0, 0] if value == 0
        abs_val = value.abs
        cat = 0
        v = abs_val
        while v > 0
          cat += 1
          v >>= 1
        end
        bits = value > 0 ? value : value + (1 << cat) - 1
        [cat, bits]
      end
    end
  end
end
