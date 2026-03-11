# frozen_string_literal: true

module PureJPEG
  # Baseline JPEG encoder.
  #
  # Encodes a pixel source into JPEG using DCT, quantization, and Huffman
  # coding. Supports grayscale (1 component) and YCbCr color (3 components,
  # 4:2:0 chroma subsampling).
  #
  # Use {PureJPEG.encode} for a convenient entry point.
  class Encoder
    # @return [#width, #height, #[]] the pixel source being encoded
    attr_reader :source
    # @return [Integer] the quality level (1-100)
    attr_reader :quality
    # @return [Boolean] whether grayscale mode is enabled
    attr_reader :grayscale
    # @return [Boolean] whether image-specific Huffman tables are generated
    attr_reader :optimize_huffman

    # Create a new encoder for the given pixel source.
    #
    # @param source [#width, #height, #[]] any object responding to +width+,
    #   +height+, and +[x, y]+ (returning an object with +.r+, +.g+, +.b+)
    # @param quality [Integer] overall compression quality, 1-100 (default 85)
    # @param grayscale [Boolean] encode as single-channel grayscale (default false)
    # @param chroma_quality [Integer, nil] independent quality for Cb/Cr channels,
    #   1-100 (defaults to +quality+)
    # @param luminance_table [Array<Integer>, nil] custom 64-element quantization
    #   table in raster order for the Y channel; overrides +quality+ for luma
    # @param chrominance_table [Array<Integer>, nil] custom 64-element quantization
    #   table in raster order for Cb/Cr channels; overrides +chroma_quality+
    # @param quantization_modifier [Proc, nil] a proc receiving +(table, channel)+
    #   where +channel+ is +:luminance+ or +:chrominance+, returning a modified
    #   table; applied after quality scaling but before encoding
    # @param scramble_quantization [Boolean] write quantization tables in raster
    #   order instead of zigzag (non-spec-compliant; recreates the "early digicam"
    #   artifact look when decoded by standard viewers)
    # @param optimize_huffman [Boolean] build image-specific Huffman tables with
    #   an additional analysis pass (default false)
    def initialize(source, quality: 85, grayscale: false, chroma_quality: nil,
                   luminance_table: nil, chrominance_table: nil,
                   quantization_modifier: nil, scramble_quantization: false,
                   optimize_huffman: false)
      @source = source
      @quality = quality
      @grayscale = grayscale
      @optimize_huffman = optimize_huffman
      @chroma_quality = chroma_quality || quality
      validate_qtable!(luminance_table, "luminance_table") if luminance_table
      validate_qtable!(chrominance_table, "chrominance_table") if chrominance_table
      @luminance_table = luminance_table
      @chrominance_table = chrominance_table
      @quantization_modifier = quantization_modifier
      @scramble_quantization = scramble_quantization
    end

    # Write the encoded JPEG to a file.
    #
    # @param path [String] output file path
    # @return [void]
    def write(path)
      File.binwrite(path, to_bytes)
    end

    # Return the encoded JPEG as a binary string.
    #
    # @return [String] raw JPEG bytes
    def to_bytes
      io = StringIO.new("".b)
      encode(io)
      io.string
    end

    private

    def build_lum_qtable
      table = @luminance_table || Quantization.scale_table(Quantization::LUMINANCE_BASE, quality)
      table = @quantization_modifier.call(table, :luminance) if @quantization_modifier
      table
    end

    def build_chr_qtable
      table = @chrominance_table || Quantization.scale_table(Quantization::CHROMINANCE_BASE, @chroma_quality)
      table = @quantization_modifier.call(table, :chrominance) if @quantization_modifier
      table
    end

    def validate_qtable!(table, name)
      raise ArgumentError, "#{name} must have exactly 64 elements (got #{table.length})" unless table.length == 64
      unless table.all? { |v| v.is_a?(Integer) && v >= 1 && v <= 255 }
        raise ArgumentError, "#{name} elements must be integers between 1 and 255"
      end
    end

    def encode(io)
      width = source.width
      height = source.height

      raise ArgumentError, "Width must be a positive integer (got #{width.inspect})" unless width.is_a?(Integer) && width > 0
      raise ArgumentError, "Height must be a positive integer (got #{height.inspect})" unless height.is_a?(Integer) && height > 0
      raise ArgumentError, "Width #{width} exceeds maximum of #{MAX_DIMENSION}" if width > MAX_DIMENSION
      raise ArgumentError, "Height #{height} exceeds maximum of #{MAX_DIMENSION}" if height > MAX_DIMENSION

      lum_qtable = build_lum_qtable

      if grayscale
        y_data = extract_luminance(width, height)
        lum_dc_bits, lum_dc_values, lum_ac_bits, lum_ac_values =
          if optimize_huffman
            counter = collect_grayscale_frequencies(y_data, width, height, lum_qtable)
            dc_bits, dc_values = Huffman.optimize_table(counter.dc_frequencies)
            ac_bits, ac_values = Huffman.optimize_table(counter.ac_frequencies)
            [dc_bits, dc_values, ac_bits, ac_values]
          else
            [Huffman::DC_LUMINANCE_BITS, Huffman::DC_LUMINANCE_VALUES,
             Huffman::AC_LUMINANCE_BITS, Huffman::AC_LUMINANCE_VALUES]
          end

        lum_huff = Huffman::Encoder.new(
          Huffman.build_table(lum_dc_bits, lum_dc_values),
          Huffman.build_table(lum_ac_bits, lum_ac_values)
        )

        scan_data = encode_grayscale_data(y_data, width, height, lum_qtable, lum_huff)
        write_grayscale_jfif(io, width, height, lum_qtable, scan_data,
                             lum_dc_bits, lum_dc_values, lum_ac_bits, lum_ac_values)
      else
        chr_qtable = build_chr_qtable
        y_data, cb_data, cr_data = extract_ycbcr(width, height)
        sub_w = (width + 1) / 2
        sub_h = (height + 1) / 2
        cb_sub = downsample(cb_data, width, height, sub_w, sub_h)
        cr_sub = downsample(cr_data, width, height, sub_w, sub_h)

        lum_dc_bits, lum_dc_values, lum_ac_bits, lum_ac_values,
          chr_dc_bits, chr_dc_values, chr_ac_bits, chr_ac_values =
          if optimize_huffman
            lum_counter, chr_counter = collect_color_frequencies(
              y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qtable, chr_qtable
            )
            dc_bits, dc_values = Huffman.optimize_table(lum_counter.dc_frequencies)
            ac_bits, ac_values = Huffman.optimize_table(lum_counter.ac_frequencies)
            chr_dc_bits, chr_dc_values = Huffman.optimize_table(chr_counter.dc_frequencies)
            chr_ac_bits, chr_ac_values = Huffman.optimize_table(chr_counter.ac_frequencies)
            [dc_bits, dc_values, ac_bits, ac_values, chr_dc_bits, chr_dc_values, chr_ac_bits, chr_ac_values]
          else
            [Huffman::DC_LUMINANCE_BITS, Huffman::DC_LUMINANCE_VALUES,
             Huffman::AC_LUMINANCE_BITS, Huffman::AC_LUMINANCE_VALUES,
             Huffman::DC_CHROMINANCE_BITS, Huffman::DC_CHROMINANCE_VALUES,
             Huffman::AC_CHROMINANCE_BITS, Huffman::AC_CHROMINANCE_VALUES]
          end

        lum_huff = Huffman::Encoder.new(
          Huffman.build_table(lum_dc_bits, lum_dc_values),
          Huffman.build_table(lum_ac_bits, lum_ac_values)
        )
        chr_huff = Huffman::Encoder.new(
          Huffman.build_table(chr_dc_bits, chr_dc_values),
          Huffman.build_table(chr_ac_bits, chr_ac_values)
        )

        scan_data = encode_color_data(
          y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qtable, chr_qtable, lum_huff, chr_huff
        )
        write_color_jfif(io, width, height, lum_qtable, chr_qtable, scan_data,
                         lum_dc_bits, lum_dc_values, lum_ac_bits, lum_ac_values,
                         chr_dc_bits, chr_dc_values, chr_ac_bits, chr_ac_values)
      end
    end

    # --- Grayscale encoding ---

    def collect_grayscale_frequencies(y_data, width, height, qtable)
      counter = Huffman::FrequencyCounter.new
      each_grayscale_block(y_data, width, height, qtable) do |zbuf|
        counter.observe_block(zbuf, :y)
      end
      counter
    end

    def encode_grayscale_data(y_data, width, height, qtable, huff)
      bit_writer = BitWriter.new
      prev_dc = 0

      each_grayscale_block(y_data, width, height, qtable) do |zbuf|
        prev_dc = huff.encode_block(zbuf, prev_dc, bit_writer)
      end

      bit_writer.flush
      bit_writer.bytes
    end

    def each_grayscale_block(y_data, width, height, qtable)
      padded_w = (width + 7) & ~7
      padded_h = (height + 7) & ~7

      block = Array.new(64, 0)
      qbuf  = Array.new(64, 0)
      zbuf  = Array.new(64, 0)

      (0...padded_h).step(8) do |by|
        (0...padded_w).step(8) do |bx|
          extract_block_into(y_data, width, height, bx, by, block)
          yield transform_block(block, qbuf, zbuf, qtable)
        end
      end
    end

    def write_grayscale_jfif(io, width, height, qtable, scan_data, dc_bits, dc_values, ac_bits, ac_values)
      jfif = JFIFWriter.new(io, scramble_quantization: @scramble_quantization)
      jfif.write_soi
      jfif.write_app0
      jfif.write_dqt(qtable, 0)
      jfif.write_sof0(width, height, [[1, 1, 1, 0]])
      jfif.write_dht(0, 0, dc_bits, dc_values)
      jfif.write_dht(1, 0, ac_bits, ac_values)
      jfif.write_sos([[1, 0, 0]])
      jfif.write_scan_data(scan_data)
      jfif.write_eoi
    end

    # --- Color encoding (YCbCr 4:2:0) ---

    def collect_color_frequencies(y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qt, chr_qt)
      lum_counter = Huffman::FrequencyCounter.new
      chr_counter = Huffman::FrequencyCounter.new

      each_color_block(y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qt, chr_qt) do |component, zbuf|
        case component
        when :y
          lum_counter.observe_block(zbuf, :y)
        when :cb
          chr_counter.observe_block(zbuf, :cb)
        when :cr
          chr_counter.observe_block(zbuf, :cr)
        end
      end

      [lum_counter, chr_counter]
    end

    def encode_color_data(y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qt, chr_qt, lum_huff, chr_huff)
      bit_writer = BitWriter.new
      prev_dc_y = 0
      prev_dc_cb = 0
      prev_dc_cr = 0

      each_color_block(y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qt, chr_qt) do |component, zbuf|
        case component
        when :y
          prev_dc_y = lum_huff.encode_block(zbuf, prev_dc_y, bit_writer)
        when :cb
          prev_dc_cb = chr_huff.encode_block(zbuf, prev_dc_cb, bit_writer)
        when :cr
          prev_dc_cr = chr_huff.encode_block(zbuf, prev_dc_cr, bit_writer)
        end
      end

      bit_writer.flush
      bit_writer.bytes
    end

    def each_color_block(y_data, cb_sub, cr_sub, width, height, sub_w, sub_h, lum_qt, chr_qt)
      mcu_w = (width + 15) & ~15
      mcu_h = (height + 15) & ~15

      block = Array.new(64, 0)
      qbuf  = Array.new(64, 0)
      zbuf  = Array.new(64, 0)

      (0...mcu_h).step(16) do |my|
        (0...mcu_w).step(16) do |mx|
          extract_block_into(y_data, width, height, mx, my, block)
          yield :y, transform_block(block, qbuf, zbuf, lum_qt)

          extract_block_into(y_data, width, height, mx + 8, my, block)
          yield :y, transform_block(block, qbuf, zbuf, lum_qt)

          extract_block_into(y_data, width, height, mx, my + 8, block)
          yield :y, transform_block(block, qbuf, zbuf, lum_qt)

          extract_block_into(y_data, width, height, mx + 8, my + 8, block)
          yield :y, transform_block(block, qbuf, zbuf, lum_qt)

          extract_block_into(cb_sub, sub_w, sub_h, mx >> 1, my >> 1, block)
          yield :cb, transform_block(block, qbuf, zbuf, chr_qt)

          extract_block_into(cr_sub, sub_w, sub_h, mx >> 1, my >> 1, block)
          yield :cr, transform_block(block, qbuf, zbuf, chr_qt)
        end
      end
    end

    def write_color_jfif(io, width, height, lum_qt, chr_qt, scan_data,
                         lum_dc_bits, lum_dc_values, lum_ac_bits, lum_ac_values,
                         chr_dc_bits, chr_dc_values, chr_ac_bits, chr_ac_values)
      jfif = JFIFWriter.new(io, scramble_quantization: @scramble_quantization)
      jfif.write_soi
      jfif.write_app0
      jfif.write_dqt(lum_qt, 0)
      jfif.write_dqt(chr_qt, 1)
      jfif.write_sof0(width, height, [[1, 2, 2, 0], [2, 1, 1, 1], [3, 1, 1, 1]])
      jfif.write_dht(0, 0, lum_dc_bits, lum_dc_values)
      jfif.write_dht(1, 0, lum_ac_bits, lum_ac_values)
      jfif.write_dht(0, 1, chr_dc_bits, chr_dc_values)
      jfif.write_dht(1, 1, chr_ac_bits, chr_ac_values)
      jfif.write_sos([[1, 0, 0], [2, 1, 1], [3, 1, 1]])
      jfif.write_scan_data(scan_data)
      jfif.write_eoi
    end

    # --- Shared block pipeline (all buffers pre-allocated) ---

    def transform_block(block, qbuf, zbuf, qtable)
      DCT.forward!(block)
      Quantization.quantize!(block, qtable, qbuf)
      Zigzag.reorder!(qbuf, zbuf)
    end

    # --- Pixel extraction ---

    # Determine RGB bit shifts for a packed_pixels source.
    # ChunkyPNG uses (r<<24 | g<<16 | b<<8 | a), Image uses (r<<16 | g<<8 | b).
    def packed_shifts
      if source.is_a?(Image)
        [16, 8, 0]
      else
        [24, 16, 8]
      end
    end

    # Fixed-point coefficients (scaled by 2^16 = 65536) for RGB→YCbCr.
    # Y  =  0.299*R + 0.587*G + 0.114*B
    # Cb = -0.168736*R - 0.331264*G + 0.5*B + 128
    # Cr =  0.5*R - 0.418688*G - 0.081312*B + 128
    FP_Y_R  =  19595; FP_Y_G  =  38470; FP_Y_B  =   7471
    FP_CB_R = -11058; FP_CB_G = -21710; FP_CB_B =  32768
    FP_CR_R =  32768; FP_CR_G = -27440; FP_CR_B =  -5328
    FP_HALF =  32768  # rounding bias
    FP_128  = 8388608 # 128 << 16
    FP_128_HALF = FP_128 + FP_HALF # merged 128 bias + rounding for Cb/Cr

    def extract_luminance(width, height)
      luminance = Array.new(width * height)
      if source.respond_to?(:packed_pixels)
        packed = source.packed_pixels
        r_shift, g_shift, b_shift = packed_shifts
        n = width * height
        i = 0
        n.times do
          color = packed[i]
          r = (color >> r_shift) & 0xFF
          g = (color >> g_shift) & 0xFF
          b = (color >> b_shift) & 0xFF
          # Y never needs clamping for valid 0-255 RGB inputs (proven exhaustively)
          luminance[i] = (FP_Y_R * r + FP_Y_G * g + FP_Y_B * b + FP_HALF) >> 16
          i += 1
        end
      else
        height.times do |py|
          row = py * width
          width.times do |px|
            pixel = source[px, py]
            r = pixel.r; g = pixel.g; b = pixel.b
            # Y never needs clamping for valid 0-255 RGB inputs (proven exhaustively)
            luminance[row + px] = (FP_Y_R * r + FP_Y_G * g + FP_Y_B * b + FP_HALF) >> 16
          end
        end
      end
      luminance
    end

    def extract_ycbcr(width, height)
      size = width * height
      y_data  = Array.new(size)
      cb_data = Array.new(size)
      cr_data = Array.new(size)

      if source.respond_to?(:packed_pixels)
        packed = source.packed_pixels
        r_shift, g_shift, b_shift = packed_shifts
        i = 0
        size.times do
          color = packed[i]
          r = (color >> r_shift) & 0xFF
          g = (color >> g_shift) & 0xFF
          b = (color >> b_shift) & 0xFF
          # Y never needs clamping for valid 0-255 RGB inputs (proven exhaustively)
          y_data[i]  = (FP_Y_R * r + FP_Y_G * g + FP_Y_B * b + FP_HALF) >> 16
          v = (FP_CB_R * r + FP_CB_G * g + FP_CB_B * b + FP_128_HALF) >> 16
          cb_data[i] = v < 0 ? 0 : (v > 255 ? 255 : v)
          v = (FP_CR_R * r + FP_CR_G * g + FP_CR_B * b + FP_128_HALF) >> 16
          cr_data[i] = v < 0 ? 0 : (v > 255 ? 255 : v)
          i += 1
        end
      else
        height.times do |py|
          row = py * width
          width.times do |px|
            pixel = source[px, py]
            r = pixel.r; g = pixel.g; b = pixel.b
            i = row + px
            # Y never needs clamping for valid 0-255 RGB inputs (proven exhaustively)
            y_data[i]  = (FP_Y_R * r + FP_Y_G * g + FP_Y_B * b + FP_HALF) >> 16
            v = (FP_CB_R * r + FP_CB_G * g + FP_CB_B * b + FP_128_HALF) >> 16
            cb_data[i] = v < 0 ? 0 : (v > 255 ? 255 : v)
            v = (FP_CR_R * r + FP_CR_G * g + FP_CR_B * b + FP_128_HALF) >> 16
            cr_data[i] = v < 0 ? 0 : (v > 255 ? 255 : v)
          end
        end
      end

      [y_data, cb_data, cr_data]
    end

    def downsample(data, src_w, src_h, dst_w, dst_h)
      out = Array.new(dst_w * dst_h)
      max_x = src_w - 1
      max_y = src_h - 1
      dst_h.times do |dy|
        sy = dy << 1
        y1 = sy < max_y ? sy + 1 : max_y
        row0 = sy * src_w
        row1 = y1 * src_w
        dst_row = dy * dst_w
        dst_w.times do |dx|
          sx = dx << 1
          x1 = sx < max_x ? sx + 1 : max_x
          out[dst_row + dx] = ((data[row0 + sx] + data[row0 + x1] +
                                data[row1 + sx] + data[row1 + x1]) >> 2)
        end
      end
      out
    end

    # Extract an 8x8 block into a pre-allocated array, level-shifted by -128.
    def extract_block_into(channel, width, height, bx, by, block)
      max_x = width - 1
      max_y = height - 1
      8.times do |row|
        sy = by + row
        sy = max_y if sy > max_y
        src = sy * width
        r8 = row << 3
        x = bx;     block[r8]     = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 1; block[r8 | 1] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 2; block[r8 | 2] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 3; block[r8 | 3] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 4; block[r8 | 4] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 5; block[r8 | 5] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 6; block[r8 | 6] = channel[src + (x > max_x ? max_x : x)] - 128
        x = bx + 7; block[r8 | 7] = channel[src + (x > max_x ? max_x : x)] - 128
      end
      block
    end
  end
end
