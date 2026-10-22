# frozen_string_literal: true

module PureJPEG
  # Baseline and progressive JPEG decoder.
  #
  # Decodes baseline (SOF0) and progressive (SOF2) 8-bit grayscale/YCbCr
  # JPEGs, including separate component scans and restart markers.
  #
  # Use {PureJPEG.read} for a convenient entry point.
  class Decoder
    # Decode a JPEG from a file path or binary string.
    #
    # @param path_or_data [String] a file path or raw JPEG bytes
    # @param max_pixels [Integer] positive maximum image area
    # @return [Image] decoded image with pixel access
    def self.decode(path_or_data, max_pixels: MAX_PIXELS)
      data = if path_or_data.is_a?(String) && !path_or_data.b.include?("\0") && !path_or_data.b.start_with?("\xFF\xD8".b) && File.exist?(path_or_data)
               File.binread(path_or_data)
             else
               path_or_data.b
             end
      new(data, max_pixels: max_pixels).decode
    end

    def initialize(data, max_pixels: MAX_PIXELS)
      unless max_pixels.is_a?(Integer) && max_pixels > 0
        raise ArgumentError, "max_pixels must be a positive Integer"
      end
      @data = data
      @max_pixels = max_pixels
    end

    def decode
      jfif = JFIFReader.new(@data, max_pixels: @max_pixels)
      @icc_profile = jfif.icc_profile
      validate_dimensions!(jfif.width, jfif.height)
      validate_frame_and_scans!(jfif)
      return decode_progressive(jfif) if jfif.progressive

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

      channels = {}
      jfif.components.each do |c|
        ch_w = mcus_x * c.h_sampling * 8
        ch_h = mcus_y * c.v_sampling * 8
        channels[c.id] = { data: Array.new(ch_w * ch_h, 0), width: ch_w, height: ch_h }
      end
      zigzag = Array.new(64, 0)
      dequant = Array.new(64, 0)

      jfif.scans.each do |scan|
        dc_tables, ac_tables = build_decode_tables(scan)
        reader = BitReader.new(scan.data)
        prev_dc = Hash.new(0)
        restart_interval = scan.restart_interval
        mcu_count = 0
        interleaved = scan.components.length > 1
        scan_components = scan.components.map do |sc|
          comp, dc_tab, ac_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables)
          [sc, comp, dc_tab, ac_tab, fetch_quant_table!(jfif, comp), channels[comp.id]]
        end
        if interleaved
          scan_width = mcus_x
          scan_height = mcus_y
        else
          comp = scan_components[0][1]
          scan_width = (width * comp.h_sampling + mcu_px_w - 1) / mcu_px_w
          scan_height = (height * comp.v_sampling + mcu_px_h - 1) / mcu_px_h
        end

        scan_height.times do |mcu_row|
          scan_width.times do |mcu_col|
            if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
              reader.read_restart((mcu_count / restart_interval - 1) % 8)
              prev_dc.clear
            end
            scan_components.each do |sc, comp, dc_tab, ac_tab, qt, ch|
              block_rows = interleaved ? comp.v_sampling : 1
              block_cols = interleaved ? comp.h_sampling : 1
              block_rows.times do |bv|
                block_cols.times do |bh|
                  decode_block(reader, dc_tab, ac_tab, prev_dc, sc.id, zigzag)
                  Quantization.dequantize_zigzag!(zigzag, qt, dequant)
                  DCT.inverse!(dequant)
                  bx = (mcu_col * block_cols + bh) * 8
                  by = (mcu_row * block_rows + bv) * 8
                  write_block(dequant, ch[:data], ch[:width], bx, by)
                end
              end
            end
            mcu_count += 1
          end
        end
        reader.finish_scan!
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

    def build_decode_tables(scan)
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
      [dc_tables, ac_tables]
    end

    def validate_frame_and_scans!(jfif)
      unless jfif.precision == 8
        raise DecodeError, "Unsupported JPEG precision: #{jfif.precision}"
      end
      count = jfif.components.length
      unless count == 1 || count == 3
        raise DecodeError, "Unsupported number of components: #{count}"
      end
      ids = jfif.components.map(&:id)
      if count == 3 && (jfif.adobe_transform == 0 || ids.sort == [66, 71, 82])
        raise DecodeError, "RGB JPEG decoding is unsupported"
      end
      if jfif.adobe_transform && ![0, 1].include?(jfif.adobe_transform)
        raise DecodeError, "Unsupported Adobe color transform: #{jfif.adobe_transform}"
      end
      raise DecodeError, "JPEG scan data not found" if jfif.scans.empty?

      progression = {}
      ids.each { |id| progression[id] = Array.new(64) }
      jfif.scans.each do |scan|
        scan_ids = scan.components.map(&:id)
        if scan_ids.empty? || scan_ids.uniq.length != scan_ids.length
          raise DecodeError, "Invalid JPEG scan components"
        end
        scan_ids.each do |id|
          raise DecodeError, "Scan references unknown component id #{id}" unless progression.key?(id)
        end
        if scan_ids.length > 1
          blocks = jfif.components.select { |c| scan_ids.include?(c.id) }.sum { |c| c.h_sampling * c.v_sampling }
          raise DecodeError, "Too many blocks in JPEG MCU" if blocks > 10
        end

        ss = scan.spectral_start
        se = scan.spectral_end
        ah = scan.successive_high
        al = scan.successive_low
        if jfif.progressive
          valid = ss <= se && se <= 63 && ah <= 13 && al <= 13 &&
                  (ss == 0 ? se == 0 : scan_ids.length == 1) &&
                  (ah == 0 || al == ah - 1)
          raise DecodeError, "Invalid progressive scan parameters" unless valid
        elsif ss != 0 || se != 63 || ah != 0 || al != 0
          raise DecodeError, "Invalid baseline scan parameters"
        end
        scan_ids.each do |id|
          state = progression[id]
          if ss > 0 && state[0].nil?
            raise DecodeError, "Progressive AC scan precedes DC scan"
          end
          ss.upto(se) do |k|
            unless ah == 0 ? state[k].nil? : state[k] == ah
              raise DecodeError, "Invalid JPEG scan progression"
            end
            state[k] = al
          end
        end
      end
      if progression.values.any? { |state| state[0].nil? }
        raise DecodeError, "JPEG scan omits a frame component"
      end
      jfif.components.each { |c| fetch_quant_table!(jfif, c) }
    end

    def validate_dimensions!(width, height)
      raise DecodeError, "JPEG frame header not found" unless width && height
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
        actual_bx = (width * c.h_sampling + mcu_px_w - 1) / mcu_px_w
        actual_by = (height * c.v_sampling + mcu_px_h - 1) / mcu_px_h
        # Interleaved scans include MCU padding; single-component scans do not.
        # Keep the storage stride separate from the actual scan dimensions.
        comp_blocks[c.id] = [bx, by, actual_bx, actual_by]
      end

      jfif.scans.each do |scan|
        restart_interval = scan.restart_interval
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
        reader.finish_scan!
      end

      # Reconstruct: unzigzag/dequantize, IDCT, write to channel buffers
      padded_w = mcus_x * mcu_px_w
      padded_h = mcus_y * mcu_px_h
      channels = {}
      jfif.components.each do |c|
        ch_w = (padded_w * c.h_sampling) / max_h
        ch_h = (padded_h * c.v_sampling) / max_v
        channels[c.id] = { data: Array.new(ch_w * ch_h, 0), width: ch_w, height: ch_h }
      end

      dequant = Array.new(64, 0)

      jfif.components.each do |c|
        qt = fetch_quant_table!(jfif, c)
        ch = channels[c.id]
        coeff_buf = coeffs[c.id]
        bx_count, by_count = comp_blocks[c.id]

        by_count.times do |block_y|
          bx_count.times do |block_x|
            offset = (block_y * bx_count + block_x) * 64
            Quantization.dequantize_zigzag!(coeff_buf, qt, dequant, offset)
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
      comp, dc_tab, ac_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables,
                                                    require_dc: ss == 0 && ah == 0, require_ac: ss > 0)
      coeff_buf = coeffs[comp.id]
      bx_count, _by_count, actual_bx, actual_by = comp_blocks[comp.id]

      prev_dc = 0
      eobrun = 0
      mcu_count = 0

      actual_by.times do |block_y|
        actual_bx.times do |block_x|
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            raise DecodeError, "Progressive EOB run crosses restart boundary" if eobrun > 0
            reader.read_restart((mcu_count / restart_interval - 1) % 8)
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
      raise DecodeError, "Progressive EOB run exceeds scan" if eobrun > 0
    end

    def prog_scan_interleaved(reader, scan, comp_info, dc_tables, ac_tables,
                              coeffs, comp_blocks, mcus_x, mcus_y, restart_interval, ss, se, ah, al)
      prev_dc = Hash.new(0)
      mcu_count = 0

      scan_components = scan.components.map do |sc|
        comp, dc_tab = resolve_scan_references!(sc, comp_info, dc_tables, ac_tables,
                                              require_dc: ah == 0, require_ac: false)
        [sc, comp, dc_tab, coeffs[comp.id], comp_blocks[comp.id][0]]
      end

      mcus_y.times do |mcu_row|
        mcus_x.times do |mcu_col|
          if restart_interval > 0 && mcu_count > 0 && (mcu_count % restart_interval) == 0
            reader.read_restart((mcu_count / restart_interval - 1) % 8)
            prev_dc.clear
          end

          scan_components.each do |sc, comp, dc_tab, coeff_buf, bx_count|
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
      cat = dc_tab.decode_symbol(reader)
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
        symbol = ac_tab.decode_symbol(reader)
        run = (symbol >> 4) & 0x0F
        size = symbol & 0x0F

        if size == 0
          if run == 15
            k += 16
            raise DecodeError, "AC run exceeds spectral band" if k > se + 1
          else
            # EOBn
            eobrun = (1 << run)
            eobrun += reader.read_bits(run) if run > 0
            return eobrun - 1
          end
        else
          k += run
          raise DecodeError, "AC run exceeds spectral band" if k > se
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
        symbol = ac_tab.decode_symbol(reader)
        r = (symbol >> 4) & 0x0F
        s = symbol & 0x0F

        # Read the new coefficient value before processing the run
        # (the value bits come before refinement bits in the bitstream)
        new_value = nil
        if s != 0
          raise DecodeError, "Invalid progressive AC refinement symbol" unless s == 1
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
        raise DecodeError, "AC refinement run exceeds spectral band" if k > se
        if new_value
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
      dc_cat = dc_tab.decode_symbol(reader)
      dc_diff = reader.receive_extend(dc_cat)
      dc_val = prev_dc[comp_id] + dc_diff
      prev_dc[comp_id] = dc_val
      out[0] = dc_val

      # AC coefficients
      i = 1
      while i < 64
        symbol = ac_tab.decode_symbol(reader)
        if symbol == 0x00 # EOB
          while i < 64
            out[i] = 0
            i += 1
          end
          break
        elsif symbol == 0xF0 # ZRL (16 zeros)
          raise DecodeError, "AC run exceeds block" if i + 16 > 64
          16.times do
            out[i] = 0
            i += 1
          end
        else
          run = (symbol >> 4) & 0x0F
          size = symbol & 0x0F
          raise DecodeError, "Invalid baseline AC symbol" if size == 0
          raise DecodeError, "AC run exceeds block" if i + run >= 64
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

    def resolve_scan_references!(scan_component, comp_info, dc_tables, ac_tables, require_dc: true, require_ac: true)
      comp = comp_info[scan_component.id]
      raise DecodeError, "Scan references unknown component id #{scan_component.id}" unless comp

      dc_tab = dc_tables[scan_component.dc_table_id]
      if require_dc && !dc_tab
        raise DecodeError, "Component #{scan_component.id} references missing DC Huffman table #{scan_component.dc_table_id}"
      end

      if require_ac
        ac_tab = ac_tables[scan_component.ac_table_id]
        raise DecodeError, "Component #{scan_component.id} references missing AC Huffman table #{scan_component.ac_table_id}" unless ac_tab
      end

      [comp, dc_tab, ac_tab]
    end

    def fetch_quant_table!(jfif, comp)
      qt = jfif.component_quant_tables[comp.id]
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
      y_h = y_comp.h_sampling
      y_v = y_comp.v_sampling
      cb_stride = cb_ch[:width]
      cr_stride = cr_ch[:width]
      cb_h = cb_comp.h_sampling
      cb_v = cb_comp.v_sampling
      cr_h = cr_comp.h_sampling
      cr_v = cr_comp.v_sampling

      pixels = Array.new(width * height)

      height.times do |py|
        dst_row = py * width
        y_row = ((py * y_v) / max_v) * y_stride

        # Chroma coordinates (nearest-neighbor upsampling)
        cb_row = ((py * cb_v) / max_v) * cb_stride
        cr_row = ((py * cr_v) / max_v) * cr_stride

        width.times do |px|
          lum = y_data[y_row + (px * y_h) / max_h]

          cb_x = (px * cb_h) / max_h
          cr_x = (px * cr_h) / max_h
          cb_val = cb_data[cb_row + cb_x] - 128
          cr_val = cr_data[cr_row + cr_x] - 128

          # Fixed-point YCbCr→RGB (all integer arithmetic)
          r = lum + ((FP_R_CR * cr_val + FP_HALF) >> 16)
          g = lum + ((FP_G_CB * cb_val + FP_G_CR * cr_val + FP_HALF) >> 16)
          b = lum + ((FP_B_CB * cb_val + FP_HALF) >> 16)

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
