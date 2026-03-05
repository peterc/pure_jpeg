# frozen_string_literal: true

module PureJPEG
  # Baseline JPEG decoder.
  #
  # Decodes baseline DCT (SOF0) JPEGs with 1 or 3 components, any chroma
  # subsampling factor, and restart markers.
  #
  # Use {PureJPEG.read} for a convenient entry point.
  class Decoder
    # Decode a JPEG from a file path or binary string.
    #
    # @param path_or_data [String] a file path or raw JPEG bytes
    # @return [Image] decoded image with pixel access
    def self.decode(path_or_data)
      data = if path_or_data.is_a?(String) && !path_or_data.include?("\x00") && File.exist?(path_or_data)
               File.binread(path_or_data)
             else
               path_or_data.b
             end
      new(data).decode
    end

    def initialize(data)
      @data = data
    end

    def decode
      jfif = JFIFReader.new(@data)
      width = jfif.width
      height = jfif.height

      # Build Huffman decode tables
      dc_tables = {}
      ac_tables = {}
      jfif.huffman_tables.each do |(table_class, table_id), info|
        table = Huffman::DecodeTable.new(info[:bits], info[:values])
        if table_class == 0
          dc_tables[table_id] = table
        else
          ac_tables[table_id] = table
        end
      end

      # Map component IDs to their info
      comp_info = {}
      jfif.components.each { |c| comp_info[c.id] = c }

      # Determine max sampling factors
      max_h = jfif.components.map(&:h_sampling).max
      max_v = jfif.components.map(&:v_sampling).max

      # MCU dimensions in pixels
      mcu_px_w = max_h * 8
      mcu_px_h = max_v * 8
      mcus_x = (width + mcu_px_w - 1) / mcu_px_w
      mcus_y = (height + mcu_px_h - 1) / mcu_px_h

      # Allocate channel buffers (full padded size)
      padded_w = mcus_x * mcu_px_w
      padded_h = mcus_y * mcu_px_h
      channels = {}
      jfif.components.each do |c|
        ch_w = (padded_w * c.h_sampling) / max_h
        ch_h = (padded_h * c.v_sampling) / max_v
        channels[c.id] = { data: Array.new(ch_w * ch_h, 0), width: ch_w, height: ch_h }
      end

      # Decode scan data
      reader = BitReader.new(jfif.scan_data)
      prev_dc = Hash.new(0)
      restart_interval = jfif.restart_interval
      mcu_count = 0

      # Reusable buffers
      zigzag = Array.new(64, 0)
      raster = Array.new(64, 0.0)
      dequant = Array.new(64, 0.0)
      temp = Array.new(64, 0.0)
      spatial = Array.new(64, 0.0)

      mcus_y.times do |mcu_row|
        mcus_x.times do |mcu_col|
          # Handle restart interval
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.reset
            prev_dc.clear
          end

          jfif.scan_components.each do |sc|
            comp = comp_info[sc.id]
            dc_tab = dc_tables[sc.dc_table_id]
            ac_tab = ac_tables[sc.ac_table_id]
            qt = jfif.quant_tables[comp.qt_id]
            ch = channels[comp.id]

            comp.v_sampling.times do |bv|
              comp.h_sampling.times do |bh|
                # Decode one 8x8 block
                decode_block(reader, dc_tab, ac_tab, prev_dc, sc.id, zigzag)

                # Inverse pipeline: unzigzag -> dequantize -> IDCT -> level shift
                Zigzag.unreorder!(zigzag, raster)
                Quantization.dequantize!(raster, qt, dequant)
                DCT.inverse!(dequant, temp, spatial)

                # Write block into channel buffer
                bx = (mcu_col * comp.h_sampling + bh) * 8
                by = (mcu_row * comp.v_sampling + bv) * 8
                write_block(spatial, ch[:data], ch[:width], bx, by)
              end
            end
          end

          mcu_count += 1
        end
      end

      # Assemble pixels
      num_components = jfif.components.length
      if num_components == 1
        assemble_grayscale(width, height, channels, jfif.components[0])
      else
        assemble_color(width, height, channels, jfif.components, max_h, max_v)
      end
    end

    private

    def decode_block(reader, dc_tab, ac_tab, prev_dc, comp_id, out)
      # DC coefficient
      dc_cat = dc_tab.decode(reader)
      dc_diff = reader.receive_extend(dc_cat)
      dc_val = prev_dc[comp_id] + dc_diff
      prev_dc[comp_id] = dc_val
      out[0] = dc_val

      # AC coefficients
      i = 1
      while i < 64
        symbol = ac_tab.decode(reader)
        if symbol == 0x00 # EOB
          while i < 64
            out[i] = 0
            i += 1
          end
          break
        elsif symbol == 0xF0 # ZRL (16 zeros)
          16.times do
            out[i] = 0
            i += 1
          end
        else
          run = (symbol >> 4) & 0x0F
          size = symbol & 0x0F
          run.times do
            out[i] = 0
            i += 1
          end
          out[i] = reader.receive_extend(size)
          i += 1
        end
      end

      out
    end

    # Write an 8x8 spatial block (level-shifted by +128) into a channel buffer.
    def write_block(spatial, channel, ch_width, bx, by)
      8.times do |row|
        dst_row = (by + row) * ch_width + bx
        row8 = row << 3
        8.times do |col|
          val = (spatial[row8 | col] + 128.0).round
          channel[dst_row + col] = val < 0 ? 0 : (val > 255 ? 255 : val)
        end
      end
    end

    def assemble_grayscale(width, height, channels, comp)
      ch = channels[comp.id]
      pixels = Array.new(width * height)
      height.times do |y|
        src_row = y * ch[:width]
        dst_row = y * width
        width.times do |x|
          v = ch[:data][src_row + x]
          pixels[dst_row + x] = Source::Pixel.new(v, v, v)
        end
      end
      Image.new(width, height, pixels)
    end

    def assemble_color(width, height, channels, components, max_h, max_v)
      # Upsample chroma channels if needed and convert YCbCr to RGB
      y_ch  = channels[components[0].id]
      cb_ch = channels[components[1].id]
      cr_ch = channels[components[2].id]

      cb_comp = components[1]
      cr_comp = components[2]

      pixels = Array.new(width * height)

      height.times do |py|
        dst_row = py * width
        y_row = py * y_ch[:width]

        # Chroma coordinates (nearest-neighbor upsampling)
        cb_y = (py * cb_comp.v_sampling) / max_v
        cr_y = (py * cr_comp.v_sampling) / max_v
        cb_row = cb_y * cb_ch[:width]
        cr_row = cr_y * cr_ch[:width]

        width.times do |px|
          lum = y_ch[:data][y_row + px]

          cb_x = (px * cb_comp.h_sampling) / max_h
          cr_x = (px * cr_comp.h_sampling) / max_h
          cb = cb_ch[:data][cb_row + cb_x] - 128.0
          cr = cr_ch[:data][cr_row + cr_x] - 128.0

          r = (lum + 1.402 * cr).round
          g = (lum - 0.344136 * cb - 0.714136 * cr).round
          b = (lum + 1.772 * cb).round

          r = r < 0 ? 0 : (r > 255 ? 255 : r)
          g = g < 0 ? 0 : (g > 255 ? 255 : g)
          b = b < 0 ? 0 : (b > 255 ? 255 : b)

          pixels[dst_row + px] = Source::Pixel.new(r, g, b)
        end
      end

      Image.new(width, height, pixels)
    end
  end
end
