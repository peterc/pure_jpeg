# frozen_string_literal: true

module PureJPEG
  class JFIFWriter
    def initialize(io, scramble_quantization: false)
      @io = io
      @scramble_quantization = scramble_quantization
    end

    def write_soi
      write_marker(0xD8)
    end

    def write_eoi
      write_marker(0xD9)
    end

    def write_app0
      write_marker(0xE0)
      data = "JFIF\0".b
      data << [1, 1].pack("CC")        # version 1.1
      data << [0].pack("C")            # density units: no units
      data << [1, 1].pack("nn")        # X/Y density
      data << [0, 0].pack("CC")        # no thumbnail
      write_length_and_data(data)
    end

    # Write a quantization table. `table_id` is 0 or 1.
    # Table is in raster order internally; DQT spec requires zigzag order.
    def write_dqt(table, table_id)
      write_marker(0xDB)
      data = [(table_id & 0x0F)].pack("C")  # 8-bit precision, table ID
      out_table = if @scramble_quantization
                    table # write raster order as-is (non-compliant, creative effect)
                  else
                    Zigzag::ORDER.map { |i| table[i] }
                  end
      data << out_table.pack("C64")
      write_length_and_data(data)
    end

    # Write Start of Frame (baseline DCT).
    # `components` is an array of [id, h_sampling, v_sampling, quant_table_id].
    def write_sof0(width, height, components)
      write_marker(0xC0)
      data = [8].pack("C")                   # 8-bit precision
      data << [height, width].pack("nn")
      data << [components.length].pack("C")
      components.each do |id, h, v, qt|
        data << [id, (h << 4) | v, qt].pack("CCC")
      end
      write_length_and_data(data)
    end

    # Write a Huffman table.
    # `table_class` is 0 for DC, 1 for AC. `table_id` is 0 or 1.
    def write_dht(table_class, table_id, bits, values)
      write_marker(0xC4)
      data = [((table_class & 1) << 4) | (table_id & 0x0F)].pack("C")
      data << bits.pack("C16")
      data << values.pack("C*")
      write_length_and_data(data)
    end

    # Write Start of Scan.
    # `components` is an array of [id, dc_table_id, ac_table_id].
    def write_sos(components)
      write_marker(0xDA)
      data = [components.length].pack("C")
      components.each do |id, dc_id, ac_id|
        data << [id, (dc_id << 4) | ac_id].pack("CC")
      end
      data << [0, 63, 0].pack("CCC")  # spectral selection start, end, approx
      write_length_and_data(data)
    end

    # Write raw scan data (already byte-stuffed).
    def write_scan_data(data)
      @io.write(data)
    end

    private

    def write_marker(code)
      @io.write([0xFF, code].pack("CC"))
    end

    def write_length_and_data(data)
      length = data.bytesize + 2  # length includes itself
      @io.write([length].pack("n"))
      @io.write(data)
    end
  end
end
