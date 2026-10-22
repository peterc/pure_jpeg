# frozen_string_literal: true

module PureJPEG
  module Huffman
    class DecodeTable
      def initialize(bits, values)
        unless bits.length == 16 && bits.all? { |n| n.is_a?(Integer) && n.between?(0, 255) } &&
               values.length.between?(1, 256) && bits.sum == values.length
          raise DecodeError, "Invalid JPEG Huffman table lengths"
        end
        available = 1
        bits.each do |count|
          available = available * 2 - count
          # JPEG reserves the all-ones code for entropy padding.
          raise DecodeError, "Oversubscribed JPEG Huffman table" if available <= 0
        end
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
      def decode_symbol(reader)
        code = 0
        len = 1
        while len <= 16
          code = (code << 1) | reader.read_bit
          if @max_code[len] >= 0 && code <= @max_code[len]
            return @values[@val_ptr[len] + code - @min_code[len]]
          end
          len += 1
        end
        raise PureJPEG::DecodeError, "Invalid Huffman code"
      end
    end
  end
end
