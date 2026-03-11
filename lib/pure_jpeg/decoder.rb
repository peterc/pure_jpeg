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
      @icc_profile = jfif.icc_profile
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
      raster = Array.new(64, 0)
      dequant = Array.new(64, 0)

      # Pre-resolve scan references and quant tables (constant per scan)
      scan_refs = jfif.scan_components.map do |sc|
        comp, dc_tab, ac_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables)
        qt = fetch_quant_table!(jfif, comp)
        ch = channels[comp.id]
        [sc, comp, dc_tab, ac_tab, qt, ch]
      end

      mcus_y.times do |mcu_row|
        mcus_x.times do |mcu_col|
          # Handle restart interval
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.reset
            prev_dc.clear
          end

          scan_refs.each do |sc, comp, dc_tab, ac_tab, qt, ch|
            comp.v_sampling.times do |bv|
              comp.h_sampling.times do |bh|
                # Decode one 8x8 block
                decode_block(reader, dc_tab, ac_tab, prev_dc, sc.id, zigzag)

                # Inverse pipeline: unzigzag -> dequantize -> IDCT -> level shift
                Zigzag.unreorder!(zigzag, raster)
                Quantization.dequantize!(raster, qt, dequant)
                DCT.inverse!(dequant)

                # Write block into channel buffer
                bx = (mcu_col * comp.h_sampling + bh) * 8
                by = (mcu_row * comp.v_sampling + bv) * 8
                write_block(dequant, ch[:data], ch[:width], bx, by)
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
      raster = Array.new(64, 0)
      dequant = Array.new(64, 0)

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
            DCT.inverse!(dequant)
            write_block(dequant, ch[:data], ch[:width], block_x * 8, block_y * 8)
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

      # Pre-resolve scan references (constant per scan)
      scan_refs = scan.components.map do |sc|
        comp, dc_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables, require_ac: false)
        coeff_buf = coeffs[comp.id]
        bx_count = comp_blocks[comp.id][0]
        [sc, comp, dc_tab, coeff_buf, bx_count]
      end

      mcus_y.times do |mcu_row|
        mcus_x.times do |mcu_col|
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.reset
            prev_dc.clear
          end

          scan_refs.each do |sc, comp, dc_tab, coeff_buf, bx_count|
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
          out[i] = 0; out[i+1] = 0; out[i+2] = 0; out[i+3] = 0
          out[i+4] = 0; out[i+5] = 0; out[i+6] = 0; out[i+7] = 0
          out[i+8] = 0; out[i+9] = 0; out[i+10] = 0; out[i+11] = 0
          out[i+12] = 0; out[i+13] = 0; out[i+14] = 0; out[i+15] = 0
          i += 16
        else
          run = (symbol >> 4) & 0x0F
          size = symbol & 0x0F
          # Use while loop for run-length zero fill (avoids block invocation)
          j = run
          while j > 0
            out[i] = 0
            i += 1
            j -= 1
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
        dst = (by + row) * ch_width + bx
        r8 = row << 3
        v = spatial[r8]     + 128; channel[dst]     = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 1] + 128; channel[dst + 1] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 2] + 128; channel[dst + 2] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 3] + 128; channel[dst + 3] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 4] + 128; channel[dst + 4] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 5] + 128; channel[dst + 5] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 6] + 128; channel[dst + 6] = v < 0 ? 0 : (v > 255 ? 255 : v)
        v = spatial[r8 | 7] + 128; channel[dst + 7] = v < 0 ? 0 : (v > 255 ? 255 : v)
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
      ch_data = ch[:data]
      ch_width = ch[:width]
      pixels = Array.new(width * height)
      height.times do |y|
        src_row = y * ch_width
        dst_row = y * width
        width.times do |x|
          v = ch_data[src_row + x]
          pixels[dst_row + x] = (v << 16) | (v << 8) | v
        end
      end
      Image.new(width, height, pixels, icc_profile: @icc_profile)
    end

    # Fixed-point coefficients (scaled by 2^16) for YCbCr→RGB.
    FP_R_CR =  91881  # 1.402    * 65536
    FP_G_CB = -22554  # -0.344136 * 65536
    FP_G_CR = -46802  # -0.714136 * 65536
    FP_B_CB = 116130  # 1.772    * 65536
    FP_HALF =  32768  # rounding bias

    def assemble_color(width, height, channels, components, max_h, max_v)
      # Upsample chroma channels if needed and convert YCbCr to RGB
      y_comp, cb_comp, cr_comp = resolve_color_components(components)

      y_ch = channels[y_comp.id]
      cb_ch = channels[cb_comp.id]
      cr_ch = channels[cr_comp.id]

      y_data = y_ch[:data]
      cb_data = cb_ch[:data]
      cr_data = cr_ch[:data]
      y_stride = y_ch[:width]
      cb_stride = cb_ch[:width]
      cr_stride = cr_ch[:width]
      cb_h = cb_comp.h_sampling
      cb_v = cb_comp.v_sampling
      cr_h = cr_comp.h_sampling
      cr_v = cr_comp.v_sampling

      pixels = Array.new(width * height)

      # Compute chroma shift factors — when sampling ratios are powers of 2
      # (which they always are in JPEG), we can replace division with right-shift.
      h_shift = 0
      t = max_h / cb_h
      while t > 1; h_shift += 1; t >>= 1; end
      v_shift = 0
      t = max_v / cb_v
      while t > 1; v_shift += 1; t >>= 1; end

      # Load fixed-point constants into locals so inner blocks use getlocal
      # instead of opt_getconstant_path (5 lookups/pixel × 1M pixels eliminated)
      fp_r_cr = FP_R_CR
      fp_g_cb = FP_G_CB
      fp_g_cr = FP_G_CR
      fp_b_cb = FP_B_CB
      fp_half = FP_HALF

      height.times do |py|
        dst_row = py * width
        y_row = py * y_stride

        # Chroma row (nearest-neighbor upsampling via shift)
        c_row = (py >> v_shift) * cb_stride

        width.times do |px|
          lum = y_data[y_row + px]

          # Cache chroma index to avoid computing c_row + cx twice
          c_idx = c_row + (px >> h_shift)
          cb_val = cb_data[c_idx] - 128
          cr_val = cr_data[c_idx] - 128

          # Fixed-point YCbCr→RGB (all integer arithmetic)
          r = lum + ((fp_r_cr * cr_val + fp_half) >> 16)
          g = lum + ((fp_g_cb * cb_val + fp_g_cr * cr_val + fp_half) >> 16)
          b = lum + ((fp_b_cb * cb_val + fp_half) >> 16)

          r = r < 0 ? 0 : (r > 255 ? 255 : r)
          g = g < 0 ? 0 : (g > 255 ? 255 : g)
          b = b < 0 ? 0 : (b > 255 ? 255 : b)

          pixels[dst_row + px] = (r << 16) | (g << 8) | b
        end
      end

      Image.new(width, height, pixels, icc_profile: @icc_profile)
    end

    def resolve_color_components(components)
      by_id = components.each_with_object({}) { |comp, memo| memo[comp.id] = comp }
      if by_id[1] && by_id[2] && by_id[3]
        [by_id[1], by_id[2], by_id[3]]
      else
        components
      end
    end
  end
end
