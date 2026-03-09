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
      data = if path_or_data.is_a?(String) && !path_or_data.start_with?("\xFF\xD8".b) && File.exist?(path_or_data)
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
      validate_dimensions!(jfif.width, jfif.height)
      return decode_progressive(jfif) if jfif.progressive

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
            comp, dc_tab, ac_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables)
            qt = fetch_quant_table!(jfif, comp)
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
      elsif num_components == 3
        assemble_color(width, height, channels, jfif.components, max_h, max_v)
      else
        raise DecodeError, "Unsupported number of components: #{num_components}"
      end
    end

    private

    def validate_dimensions!(width, height)
      raise DecodeError, "Invalid image dimensions: #{width}x#{height}" if width <= 0 || height <= 0
      raise DecodeError, "Image too large: #{width}x#{height} (max #{MAX_DIMENSION}x#{MAX_DIMENSION})" if width > MAX_DIMENSION || height > MAX_DIMENSION
    end

    # --- Progressive JPEG decoding ---

    def decode_progressive(jfif)
      width = jfif.width
      height = jfif.height

      comp_info = {}
      jfif.components.each { |c| comp_info[c.id] = c }

      max_h = jfif.components.map(&:h_sampling).max
      max_v = jfif.components.map(&:v_sampling).max

      mcu_px_w = max_h * 8
      mcu_px_h = max_v * 8
      mcus_x = (width + mcu_px_w - 1) / mcu_px_w
      mcus_y = (height + mcu_px_h - 1) / mcu_px_h

      # Coefficient buffers per component (zigzag order, pre-dequantization)
      coeffs = {}
      comp_blocks = {}
      jfif.components.each do |c|
        bx = mcus_x * c.h_sampling
        by = mcus_y * c.v_sampling
        coeffs[c.id] = Array.new(bx * by * 64, 0)
        comp_blocks[c.id] = [bx, by]
      end

      restart_interval = jfif.restart_interval

      jfif.scans.each do |scan|
        # Build Huffman tables from this scan's snapshot (tables change between scans)
        dc_tables = {}
        ac_tables = {}
        scan.huffman_tables.each do |(table_class, table_id), info|
          table = Huffman::DecodeTable.new(info[:bits], info[:values])
          if table_class == 0
            dc_tables[table_id] = table
          else
            ac_tables[table_id] = table
          end
        end

        reader = BitReader.new(scan.data)
        ss = scan.spectral_start
        se = scan.spectral_end
        ah = scan.successive_high
        al = scan.successive_low

        if scan.components.length == 1
          prog_scan_non_interleaved(reader, scan, comp_info, dc_tables, ac_tables,
                                    coeffs, comp_blocks, restart_interval, ss, se, ah, al)
        else
          prog_scan_interleaved(reader, scan, comp_info, dc_tables, ac_tables,
                                coeffs, comp_blocks, mcus_x, mcus_y, restart_interval, ss, se, ah, al)
        end
      end

      # Reconstruct: unzigzag, dequantize, IDCT, write to channel buffers
      padded_w = mcus_x * mcu_px_w
      padded_h = mcus_y * mcu_px_h
      channels = {}
      jfif.components.each do |c|
        ch_w = (padded_w * c.h_sampling) / max_h
        ch_h = (padded_h * c.v_sampling) / max_v
        channels[c.id] = { data: Array.new(ch_w * ch_h, 0), width: ch_w, height: ch_h }
      end

      zigzag = Array.new(64, 0)
      raster = Array.new(64, 0.0)
      dequant = Array.new(64, 0.0)
      temp = Array.new(64, 0.0)
      spatial = Array.new(64, 0.0)

      jfif.components.each do |c|
        qt = fetch_quant_table!(jfif, c)
        ch = channels[c.id]
        coeff_buf = coeffs[c.id]
        bx_count, by_count = comp_blocks[c.id]

        by_count.times do |block_y|
          bx_count.times do |block_x|
            offset = (block_y * bx_count + block_x) * 64
            64.times { |i| zigzag[i] = coeff_buf[offset + i] }

            Zigzag.unreorder!(zigzag, raster)
            Quantization.dequantize!(raster, qt, dequant)
            DCT.inverse!(dequant, temp, spatial)
            write_block(spatial, ch[:data], ch[:width], block_x * 8, block_y * 8)
          end
        end
      end

      num_components = jfif.components.length
      if num_components == 1
        assemble_grayscale(width, height, channels, jfif.components[0])
      elsif num_components == 3
        assemble_color(width, height, channels, jfif.components, max_h, max_v)
      else
        raise DecodeError, "Unsupported number of components: #{num_components}"
      end
    end

    def prog_scan_non_interleaved(reader, scan, comp_info, dc_tables, ac_tables,
                                  coeffs, comp_blocks, restart_interval, ss, se, ah, al)
      sc = scan.components[0]
      comp, dc_tab, ac_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables, require_ac: ss > 0)
      coeff_buf = coeffs[comp.id]
      bx_count, by_count = comp_blocks[comp.id]

      prev_dc = 0
      eobrun = 0
      mcu_count = 0

      by_count.times do |block_y|
        bx_count.times do |block_x|
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.reset
            prev_dc = 0
            eobrun = 0
          end

          offset = (block_y * bx_count + block_x) * 64

          if ss == 0
            if ah == 0
              prev_dc = prog_dc_first(reader, dc_tab, prev_dc, coeff_buf, offset, al)
            else
              prog_dc_refine(reader, coeff_buf, offset, al)
            end
          else
            if ah == 0
              eobrun = prog_ac_first(reader, ac_tab, coeff_buf, offset, ss, se, al, eobrun)
            else
              eobrun = prog_ac_refine(reader, ac_tab, coeff_buf, offset, ss, se, al, eobrun)
            end
          end

          mcu_count += 1
        end
      end
    end

    def prog_scan_interleaved(reader, scan, comp_info, dc_tables, ac_tables,
                              coeffs, comp_blocks, mcus_x, mcus_y, restart_interval, ss, se, ah, al)
      prev_dc = Hash.new(0)
      mcu_count = 0

      mcus_y.times do |mcu_row|
        mcus_x.times do |mcu_col|
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.reset
            prev_dc.clear
          end

          scan.components.each do |sc|
            comp, dc_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables, require_ac: false)
            coeff_buf = coeffs[comp.id]
            bx_count = comp_blocks[comp.id][0]

            comp.v_sampling.times do |bv|
              comp.h_sampling.times do |bh|
                block_x = mcu_col * comp.h_sampling + bh
                block_y = mcu_row * comp.v_sampling + bv
                offset = (block_y * bx_count + block_x) * 64

                if ah == 0
                  prev_dc[sc.id] = prog_dc_first(reader, dc_tab, prev_dc[sc.id], coeff_buf, offset, al)
                else
                  prog_dc_refine(reader, coeff_buf, offset, al)
                end
              end
            end
          end

          mcu_count += 1
        end
      end
    end

    def prog_dc_first(reader, dc_tab, prev_dc, coeff_buf, offset, al)
      cat = dc_tab.decode(reader)
      diff = reader.receive_extend(cat)
      dc_val = prev_dc + diff
      coeff_buf[offset] = dc_val << al
      dc_val
    end

    def prog_dc_refine(reader, coeff_buf, offset, al)
      coeff_buf[offset] |= (reader.read_bit << al)
    end

    def prog_ac_first(reader, ac_tab, coeff_buf, offset, ss, se, al, eobrun)
      return eobrun - 1 if eobrun > 0

      k = ss
      while k <= se
        symbol = ac_tab.decode(reader)
        run = (symbol >> 4) & 0x0F
        size = symbol & 0x0F

        if size == 0
          if run == 15
            k += 16
          else
            # EOBn
            eobrun = (1 << run)
            eobrun += reader.read_bits(run) if run > 0
            return eobrun - 1
          end
        else
          k += run
          coeff_buf[offset + k] = reader.receive_extend(size) << al
          k += 1
        end
      end

      0
    end

    def prog_ac_refine(reader, ac_tab, coeff_buf, offset, ss, se, al, eobrun)
      p1 = 1 << al
      m1 = -(1 << al)

      if eobrun > 0
        ss.upto(se) do |k|
          prog_refine_bit(reader, coeff_buf, offset + k, p1, m1) if coeff_buf[offset + k] != 0
        end
        return eobrun - 1
      end

      k = ss
      while k <= se
        symbol = ac_tab.decode(reader)
        r = (symbol >> 4) & 0x0F
        s = symbol & 0x0F

        # Read the new coefficient value before processing the run
        # (the value bits come before refinement bits in the bitstream)
        new_value = nil
        if s != 0
          new_value = reader.receive_extend(s) << al
        elsif r != 15
          # EOBn: refine remaining nonzero coefficients in this block
          eobrun = (1 << r)
          eobrun += reader.read_bits(r) if r > 0
          while k <= se
            prog_refine_bit(reader, coeff_buf, offset + k, p1, m1) if coeff_buf[offset + k] != 0
            k += 1
          end
          return eobrun - 1
        end

        # Advance through the band: refine nonzero coefficients, count zeros for run.
        # Break when we've skipped `r` zeros and found the target zero position.
        while k <= se
          if coeff_buf[offset + k] != 0
            prog_refine_bit(reader, coeff_buf, offset + k, p1, m1)
          elsif r == 0
            break
          else
            r -= 1
          end
          k += 1
        end

        # Place new coefficient at the target zero position
        if new_value && k <= se
          coeff_buf[offset + k] = new_value
        end
        k += 1
      end

      0
    end

    def prog_refine_bit(reader, coeff_buf, idx, p1, m1)
      if reader.read_bit == 1
        coeff_buf[idx] += coeff_buf[idx] > 0 ? p1 : m1
      end
    end

    # --- Baseline decoding helpers ---

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

    def resolve_scan_references!(scan_component, comp_info, dc_tables, ac_tables, require_ac: true)
      comp = comp_info[scan_component.id]
      raise DecodeError, "Scan references unknown component id #{scan_component.id}" unless comp

      dc_tab = dc_tables[scan_component.dc_table_id]
      raise DecodeError, "Component #{scan_component.id} references missing DC Huffman table #{scan_component.dc_table_id}" unless dc_tab

      if require_ac
        ac_tab = ac_tables[scan_component.ac_table_id]
        raise DecodeError, "Component #{scan_component.id} references missing AC Huffman table #{scan_component.ac_table_id}" unless ac_tab
      end

      [comp, dc_tab, ac_tab]
    end

    def fetch_quant_table!(jfif, comp)
      qt = jfif.quant_tables[comp.qt_id]
      raise DecodeError, "Component #{comp.id} references missing quantization table #{comp.qt_id}" unless qt

      qt
    end

    def assemble_grayscale(width, height, channels, comp)
      ch = channels[comp.id]
      pixels = Array.new(width * height)
      height.times do |y|
        src_row = y * ch[:width]
        dst_row = y * width
        width.times do |x|
          v = ch[:data][src_row + x]
          pixels[dst_row + x] = (v << 16) | (v << 8) | v
        end
      end
      Image.new(width, height, pixels)
    end

    def assemble_color(width, height, channels, components, max_h, max_v)
      # Upsample chroma channels if needed and convert YCbCr to RGB
      by_id = components.each_with_object({}) { |comp, memo| memo[comp.id] = comp }
      y_comp = by_id[1]
      cb_comp = by_id[2]
      cr_comp = by_id[3]

      unless y_comp && cb_comp && cr_comp
        ids = components.map(&:id).sort.join(", ")
        raise DecodeError, "Unsupported 3-component JPEG: expected YCbCr component ids 1, 2, 3 (got #{ids})"
      end

      y_ch = channels[y_comp.id]
      cb_ch = channels[cb_comp.id]
      cr_ch = channels[cr_comp.id]

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

          pixels[dst_row + px] = (r << 16) | (g << 8) | b
        end
      end

      Image.new(width, height, pixels)
    end
  end
end
