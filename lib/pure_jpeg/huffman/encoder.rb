# frozen_string_literal: true

module PureJPEG
  module Huffman
    class Encoder
      # Return the Huffman category (bit length) for a value.
      # Uses Integer#bit_length (C-implemented) which is ~1.6x faster
      # than a manual while-loop for typical DCT coefficient values.
      def self.category(value)
        value.abs.bit_length
      end

      # Return the extra bits to encode for a value with the given category.
      def self.value_bits(value, cat)
        value > 0 ? value : value + (1 << cat) - 1
      end

      def self.each_ac_item(zigzag)
        last_nonzero = 63
        last_nonzero -= 1 while last_nonzero > 0 && zigzag[last_nonzero] == 0

        if last_nonzero == 0
          yield 0x00, 0
          return
        end

        i = 1
        while i <= last_nonzero
          run = 0
          while i <= last_nonzero && zigzag[i] == 0
            run += 1
            i += 1
          end

          while run >= 16
            yield 0xF0, 0
            run -= 16
          end

          value = zigzag[i]
          cat = category(value)
          yield (run << 4) | cat, value
          i += 1
        end

        yield 0x00, 0 if last_nonzero < 63
      end

      def self.each_ac_symbol(zigzag)
        each_ac_item(zigzag) do |symbol, _value|
          yield symbol
        end
      end

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
        cat = self.class.category(diff)
        code, length = @dc_table[cat]
        writer.write_bits(code, length)
        writer.write_bits(self.class.value_bits(diff, cat), cat) if cat > 0
      end

      def encode_ac(zigzag, writer)
        self.class.each_ac_item(zigzag) do |symbol, value|
          code, length = @ac_table[symbol]
          writer.write_bits(code, length)
          next if symbol == 0x00 || symbol == 0xF0

          cat = self.class.category(value)
          writer.write_bits(self.class.value_bits(value, cat), cat)
        end
      end
    end

    class FrequencyCounter
      attr_reader :dc_frequencies, :ac_frequencies

      def initialize
        @dc_frequencies = Array.new(256, 0)
        @ac_frequencies = Array.new(256, 0)
        @prev_dc = Hash.new(0)
      end

      def observe_block(zigzag, state_key)
        diff = zigzag[0] - @prev_dc[state_key]
        @prev_dc[state_key] = zigzag[0]

        cat = Encoder.category(diff)
        @dc_frequencies[cat] += 1

        Encoder.each_ac_symbol(zigzag) do |symbol|
          @ac_frequencies[symbol] += 1
        end
      end
    end
  end
end
