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

    # Each component holds one frame MCU row of samples (and, for progressive
    # scans, coefficients). Each scan keeps its own entropy position across rows.
    ComponentStrip = Struct.new(:component, :block_columns, :scan_columns, :scan_rows,
                                :quant_table, :samples, :coefficients)
    ScanState = Struct.new(:scan, :reader, :mcu_blocks, :prev_dc, :mcu_count, :eobrun)
    private_constant :ComponentStrip, :ScanState

    def decode
      jfif = JFIFReader.new(@data, max_pixels: @max_pixels)
      width = jfif.width
      height = jfif.height
      validate_dimensions!(width, height)
      validate_frame_and_scans!(jfif)

      max_h = jfif.components.map(&:h_sampling).max
      max_v = jfif.components.map(&:v_sampling).max
      mcu_width = max_h * 8
      strip_height = max_v * 8
      mcu_columns = (width + mcu_width - 1) / mcu_width
      strips = {}
      jfif.components.each do |comp|
        block_columns = mcu_columns * comp.h_sampling
        size = block_columns * comp.v_sampling * 64
        scan_columns = (width * comp.h_sampling + mcu_width - 1) / mcu_width
        scan_rows = (height * comp.v_sampling + strip_height - 1) / strip_height
        coeffs = Array.new(size, 0) if jfif.progressive
        strips[comp.id] = ComponentStrip.new(comp, block_columns, scan_columns, scan_rows,
                                             fetch_quant_table!(jfif, comp), Array.new(size, 0), coeffs)
      end
      ordered_strips = resolve_color_components(jfif.components).map { |comp| strips[comp.id] }
      states = jfif.scans.map { |scan| build_scan_state(scan, strips, jfif.progressive) }
      pixels = Array.new(width * height, 0)
      zigzag = Array.new(64, 0)
      dequant = Array.new(64, 0)

      # Scans refine the same blocks in file order. Predictors, restart counts,
      # and EOB runs belong to their scan and continue into the next strip.
      (0...height).step(strip_height) do |top|
        states.each do |state|
          decode_scan_strip(state, top / strip_height, mcu_columns, jfif.progressive, zigzag, dequant)
        end
        if jfif.progressive
          ordered_strips.each { |strip| reconstruct_strip(strip, dequant) }
        end
        rows = [strip_height, height - top].min
        if ordered_strips.length == 1
          assemble_grayscale(pixels, width, top, rows, ordered_strips.first)
        else
          assemble_color(pixels, width, top, rows, ordered_strips, max_h, max_v)
        end
      end
      states.each do |state|
        raise DecodeError, "Progressive EOB run exceeds scan" if state.eobrun > 0
        state.reader.finish_scan!
      end
      Image.new(width, height, pixels, icc_profile: jfif.icc_profile)
    end

    private

    def build_scan_state(scan, strips, progressive)
      dc_tables, ac_tables = build_decode_tables(scan)
      require_dc = !progressive || (scan.spectral_start == 0 && scan.successive_high == 0)
      require_ac = !progressive || scan.spectral_start > 0
      interleaved = scan.components.length > 1
      blocks = []
      scan.components.each do |sc|
        strip = strips.fetch(sc.id)
        dc = dc_tables[sc.dc_table_id]
        ac = ac_tables[sc.ac_table_id]
        if require_dc && !dc
          raise DecodeError, "Component #{sc.id} references missing DC Huffman table #{sc.dc_table_id}"
        end
        if require_ac && !ac
          raise DecodeError, "Component #{sc.id} references missing AC Huffman table #{sc.ac_table_id}"
        end
        # Precompute the block layout of an MCU once for this scan.
        h_blocks = interleaved ? strip.component.h_sampling : 1
        v_blocks = interleaved ? strip.component.v_sampling : 1
        v_blocks.times do |dy|
          h_blocks.times { |dx| blocks << [strip, dc, ac, h_blocks, dx, dy] }
        end
      end
      ScanState.new(scan, BitReader.new(scan.data), blocks, Hash.new(0), 0, 0)
    end

    def decode_scan_strip(state, strip_index, mcu_columns, progressive, zigzag, dequant)
      scan = state.scan
      reader = state.reader
      interval = scan.restart_interval
      blocks = state.mcu_blocks
      columns = mcu_columns
      rows = 1
      if scan.components.length == 1
        # A non-interleaved MCU is one block. Omit the frame's padding blocks
        # at the right and bottom edges while keeping the padded storage stride.
        strip = blocks.first[0]
        v = strip.component.v_sampling
        columns = strip.scan_columns
        rows = [v, strip.scan_rows - strip_index * v].min
        return decode_ac_strip(state, rows, columns) if scan.spectral_start > 0
      end

      count = state.mcu_count
      rows.times do |row|
        columns.times do |col|
          if interval > 0 && count > 0 && (count % interval) == 0
            reader.read_restart((count / interval - 1) % 8)
            state.prev_dc.clear
          end
          # An indexed loop avoids a per-MCU closure allocation on Spinel.
          index = 0
          while index < blocks.length
            strip, dc, ac, h_blocks, dx, dy = blocks[index]
            index += 1
            bx = col * h_blocks + dx
            by = row + dy
            if progressive
              offset = (by * strip.block_columns + bx) * 64
              coeffs = strip.coefficients
              if scan.successive_high == 0
                id = strip.component.id
                state.prev_dc[id] = prog_dc_first(reader, dc, state.prev_dc[id], coeffs, offset, scan.successive_low)
              else
                prog_dc_refine(reader, coeffs, offset, scan.successive_low)
              end
            else
              decode_block(reader, dc, ac, state.prev_dc, strip.component.id, zigzag)
              Quantization.dequantize_zigzag!(zigzag, strip.quant_table, dequant)
              DCT.inverse!(dequant)
              write_block(dequant, strip.samples, strip.block_columns * 8, bx * 8, by * 8)
            end
          end
          count += 1
        end
      end
      state.mcu_count = count
    end

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

    # Progressive AC scans always visit one block per MCU. An EOB run may
    # span several rows, including the boundary between two strips.
    def decode_ac_strip(state, rows, columns)
      strip, _dc, ac = state.mcu_blocks.first
      coeffs = strip.coefficients
      scan = state.scan
      reader = state.reader
      ss = scan.spectral_start
      se = scan.spectral_end
      al = scan.successive_low
      first = scan.successive_high == 0
      interval = scan.restart_interval
      count = state.mcu_count
      eobrun = state.eobrun
      rows.times do |row|
        offset = row * strip.block_columns * 64
        columns.times do
          if interval > 0 && count > 0 && (count % interval) == 0
            raise DecodeError, "Progressive EOB run crosses restart boundary" if eobrun > 0
            reader.read_restart((count / interval - 1) % 8)
          end
          if first
            eobrun = prog_ac_first(reader, ac, coeffs, offset, ss, se, al, eobrun)
          else
            eobrun = prog_ac_refine(reader, ac, coeffs, offset, ss, se, al, eobrun)
          end
          count += 1
          offset += 64
        end
      end
      state.mcu_count = count
      state.eobrun = eobrun
    end

    def reconstruct_strip(strip, dequant)
      coeffs = strip.coefficients
      columns = strip.block_columns
      strip.component.v_sampling.times do |by|
        columns.times do |bx|
          offset = (by * columns + bx) * 64
          Quantization.dequantize_zigzag!(coeffs, strip.quant_table, dequant, offset)
          DCT.inverse!(dequant)
          write_block(dequant, strip.samples, columns * 8, bx * 8, by * 8)
        end
      end
      coeffs.fill(0)
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

    def fetch_quant_table!(jfif, comp)
      qt = jfif.component_quant_tables[comp.id]
      raise DecodeError, "Component #{comp.id} references missing quantization table #{comp.qt_id}" unless qt

      qt
    end

    def assemble_grayscale(pixels, width, top, height, strip)
      ch_data = strip.samples
      ch_width = strip.block_columns * 8
      height.times do |y|
        src_row = y * ch_width
        dst_row = (top + y) * width
        width.times do |x|
          v = ch_data[src_row + x]
          pixels[dst_row + x] = (v << 16) | (v << 8) | v
        end
      end
    end

    # Fixed-point coefficients (scaled by 2^16) for YCbCr→RGB.
    FP_R_CR =  91881  # 1.402    * 65536
    FP_G_CB = -22554  # -0.344136 * 65536
    FP_G_CR = -46802  # -0.714136 * 65536
    FP_B_CB = 116130  # 1.772    * 65536
    FP_HALF =  32768  # rounding bias

    def assemble_color(pixels, width, top, height, strips, max_h, max_v)
      y_ch, cb_ch, cr_ch = strips
      y_data = y_ch.samples
      cb_data = cb_ch.samples
      cr_data = cr_ch.samples
      y_stride = y_ch.block_columns * 8
      y_h = y_ch.component.h_sampling
      y_v = y_ch.component.v_sampling
      cb_stride = cb_ch.block_columns * 8
      cr_stride = cr_ch.block_columns * 8
      cb_h = cb_ch.component.h_sampling
      cb_v = cb_ch.component.v_sampling
      cr_h = cr_ch.component.h_sampling
      cr_v = cr_ch.component.v_sampling

      height.times do |py|
        dst_row = (top + py) * width
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
