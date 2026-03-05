# frozen_string_literal: true

module PureJPEG
  module Huffman
    class DecodeTable
      def initialize(bits, values)
        @min_code = Array.new(17, 0)
        @max_code = Array.new(17, -1)
        @val_ptr = Array.new(17, 0)
        @values = values

        code = 0
        k = 0
        16.times do |i|
          len = i + 1
          @val_ptr[len] = k
          if bits[i] > 0
            @min_code[len] = code
            code += bits[i]
            @max_code[len] = code - 1
            k += bits[i]
          end
          code <<= 1
        end
      end

      # Decode one Huffman symbol from the bit reader.
      def decode(reader)
        code = 0
        1.upto(16) do |len|
          code = (code << 1) | reader.read_bit
          if @max_code[len] >= 0 && code <= @max_code[len]
            return @values[@val_ptr[len] + code - @min_code[len]]
          end
        end
        raise "Invalid Huffman code"
      end
    end
  end
end
