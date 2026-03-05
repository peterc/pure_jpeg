# frozen_string_literal: true

module PureJPEG
  class BitReader
    def initialize(data)
      @data = data
      @pos = 0
      @length = data.bytesize
      @buffer = 0
      @bits_in_buffer = 0
    end

    def read_bit
      fill_buffer if @bits_in_buffer == 0
      @bits_in_buffer -= 1
      (@buffer >> @bits_in_buffer) & 1
    end

    def read_bits(n)
      return 0 if n == 0
      value = 0
      n.times { value = (value << 1) | read_bit }
      value
    end

    # Discard remaining bits in the buffer (for restart marker boundaries).
    def reset
      @bits_in_buffer = 0
      @buffer = 0
    end

    # Read additional bits and sign-extend per JPEG spec (receive/extend).
    def receive_extend(size)
      return 0 if size == 0
      bits = read_bits(size)
      if bits < (1 << (size - 1))
        bits - (1 << size) + 1
      else
        bits
      end
    end

    private

    def fill_buffer
      raise "Unexpected end of scan data" if @pos >= @length
      byte = @data.getbyte(@pos)
      @pos += 1
      if byte == 0xFF
        next_byte = @data.getbyte(@pos)
        @pos += 1
        # 0xFF 0x00 is a stuffed 0xFF byte
        # Skip restart markers (0xD0-0xD7)
        return fill_buffer if next_byte != 0x00 && next_byte >= 0xD0 && next_byte <= 0xD7
        # For 0x00, the byte is 0xFF (stuffing removed)
      end
      @buffer = byte
      @bits_in_buffer = 8
    end
  end
end
