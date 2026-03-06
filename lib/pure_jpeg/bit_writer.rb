# frozen_string_literal: true

module PureJPEG
  class BitWriter
    def initialize
      @data = String.new(capacity: 4096, encoding: Encoding::BINARY)
      @buffer = 0
      @bits_in_buffer = 0
    end

    # Write `num_bits` of `value` (MSB first) into the output stream.
    def write_bits(value, num_bits)
      return if num_bits == 0
      @buffer = (@buffer << num_bits) | (value & ((1 << num_bits) - 1))
      @bits_in_buffer += num_bits

      while @bits_in_buffer >= 8
        @bits_in_buffer -= 8
        byte = (@buffer >> @bits_in_buffer) & 0xFF
        @data << byte.chr
        @data << "\x00".b if byte == 0xFF  # byte stuffing
      end

      @buffer &= (1 << @bits_in_buffer) - 1
    end

    # Pad remaining bits with 1s and flush (per JPEG spec).
    def flush
      return unless @bits_in_buffer > 0
      padding = 8 - @bits_in_buffer
      write_bits((1 << padding) - 1, padding)
    end

    def bytes
      @data
    end
  end
end
