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
    def initialize(source, quality: 85, grayscale: false, chroma_quality: nil,
                   luminance_table: nil, chrominance_table: nil,
                   quantization_modifier: nil, scramble_quantization: false)
      @source = source
      @quality = quality
      @grayscale = grayscale
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
      File.open(path, "wb") { |f| encode(f) }
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
      lum_dc = Huffman.build_table(Huffman::DC_LUMINANCE_BITS, Huffman::DC_LUMINANCE_VALUES)
      lum_ac = Huffman.build_table(Huffman::AC_LUMINANCE_BITS, Huffman::AC_LUMINANCE_VALUES)
      lum_huff = Huffman::Encoder.new(lum_dc, lum_ac)

      if grayscale
        scan_data = encode_grayscale(width, height, lum_qtable, lum_huff)
        write_grayscale_jfif(io, width, height, lum_qtable, scan_data)
      else
        chr_qtable = build_chr_qtable
        chr_dc = Huffman.build_table(Huffman::DC_CHROMINANCE_BITS, Huffman::DC_CHROMINANCE_VALUES)
        chr_ac = Huffman.build_table(Huffman::AC_CHROMINANCE_BITS, Huffman::AC_CHROMINANCE_VALUES)
        chr_huff = Huffman::Encoder.new(chr_dc, chr_ac)

        scan_data = encode_color(width, height, lum_qtable, chr_qtable, lum_huff, chr_huff)
        write_color_jfif(io, width, height, lum_qtable, chr_qtable, scan_data)
      end
    end

    # --- Grayscale encoding ---

    def encode_grayscale(width, height, qtable, huff)
      y_data = extract_luminance(width, height)
      padded_w = (width + 7) & ~7
      padded_h = (height + 7) & ~7

      # Reusable buffers
      block = Array.new(64, 0.0)
      temp  = Array.new(64, 0.0)
      dct   = Array.new(64, 0.0)
      qbuf  = Array.new(64, 0)
      zbuf  = Array.new(64, 0)

      bit_writer = BitWriter.new
      prev_dc = 0

      (0...padded_h).step(8) do |by|
        (0...padded_w).step(8) do |bx|
          extract_block_into(y_data, width, height, bx, by, block)
          prev_dc = encode_block(block, temp, dct, qbuf, zbuf, qtable, huff, prev_dc, bit_writer)
        end
      end

      bit_writer.flush
      bit_writer.bytes
    end

    def write_grayscale_jfif(io, width, height, qtable, scan_data)
      jfif = JFIFWriter.new(io, scramble_quantization: @scramble_quantization)
      jfif.write_soi
      jfif.write_app0
      jfif.write_dqt(qtable, 0)
      jfif.write_sof0(width, height, [[1, 1, 1, 0]])
      jfif.write_dht(0, 0, Huffman::DC_LUMINANCE_BITS, Huffman::DC_LUMINANCE_VALUES)
      jfif.write_dht(1, 0, Huffman::AC_LUMINANCE_BITS, Huffman::AC_LUMINANCE_VALUES)
      jfif.write_sos([[1, 0, 0]])
      jfif.write_scan_data(scan_data)
      jfif.write_eoi
    end

    # --- Color encoding (YCbCr 4:2:0) ---

    def encode_color(width, height, lum_qt, chr_qt, lum_huff, chr_huff)
      y_data, cb_data, cr_data = extract_ycbcr(width, height)

      sub_w = (width + 1) / 2
      sub_h = (height + 1) / 2
      cb_sub = downsample(cb_data, width, height, sub_w, sub_h)
      cr_sub = downsample(cr_data, width, height, sub_w, sub_h)

      mcu_w = (width + 15) & ~15
      mcu_h = (height + 15) & ~15

      # Reusable buffers
      block = Array.new(64, 0.0)
      temp  = Array.new(64, 0.0)
      dct   = Array.new(64, 0.0)
      qbuf  = Array.new(64, 0)
      zbuf  = Array.new(64, 0)

      bit_writer = BitWriter.new
      prev_dc_y = 0
      prev_dc_cb = 0
      prev_dc_cr = 0

      (0...mcu_h).step(16) do |my|
        (0...mcu_w).step(16) do |mx|
          # 4 luminance blocks
          extract_block_into(y_data, width, height, mx, my, block)
          prev_dc_y = encode_block(block, temp, dct, qbuf, zbuf, lum_qt, lum_huff, prev_dc_y, bit_writer)

          extract_block_into(y_data, width, height, mx + 8, my, block)
          prev_dc_y = encode_block(block, temp, dct, qbuf, zbuf, lum_qt, lum_huff, prev_dc_y, bit_writer)

          extract_block_into(y_data, width, height, mx, my + 8, block)
          prev_dc_y = encode_block(block, temp, dct, qbuf, zbuf, lum_qt, lum_huff, prev_dc_y, bit_writer)

          extract_block_into(y_data, width, height, mx + 8, my + 8, block)
          prev_dc_y = encode_block(block, temp, dct, qbuf, zbuf, lum_qt, lum_huff, prev_dc_y, bit_writer)

          # 1 Cb block
          extract_block_into(cb_sub, sub_w, sub_h, mx >> 1, my >> 1, block)
          prev_dc_cb = encode_block(block, temp, dct, qbuf, zbuf, chr_qt, chr_huff, prev_dc_cb, bit_writer)

          # 1 Cr block
          extract_block_into(cr_sub, sub_w, sub_h, mx >> 1, my >> 1, block)
          prev_dc_cr = encode_block(block, temp, dct, qbuf, zbuf, chr_qt, chr_huff, prev_dc_cr, bit_writer)
        end
      end

      bit_writer.flush
      bit_writer.bytes
    end

    def write_color_jfif(io, width, height, lum_qt, chr_qt, scan_data)
      jfif = JFIFWriter.new(io, scramble_quantization: @scramble_quantization)
      jfif.write_soi
      jfif.write_app0
      jfif.write_dqt(lum_qt, 0)
      jfif.write_dqt(chr_qt, 1)
      jfif.write_sof0(width, height, [[1, 2, 2, 0], [2, 1, 1, 1], [3, 1, 1, 1]])
      jfif.write_dht(0, 0, Huffman::DC_LUMINANCE_BITS, Huffman::DC_LUMINANCE_VALUES)
      jfif.write_dht(1, 0, Huffman::AC_LUMINANCE_BITS, Huffman::AC_LUMINANCE_VALUES)
      jfif.write_dht(0, 1, Huffman::DC_CHROMINANCE_BITS, Huffman::DC_CHROMINANCE_VALUES)
      jfif.write_dht(1, 1, Huffman::AC_CHROMINANCE_BITS, Huffman::AC_CHROMINANCE_VALUES)
      jfif.write_sos([[1, 0, 0], [2, 1, 1], [3, 1, 1]])
      jfif.write_scan_data(scan_data)
      jfif.write_eoi
    end

    # --- Shared block pipeline (all buffers pre-allocated) ---

    def encode_block(block, temp, dct, qbuf, zbuf, qtable, huff, prev_dc, bit_writer)
      DCT.forward!(block, temp, dct)
      Quantization.quantize!(dct, qtable, qbuf)
      Zigzag.reorder!(qbuf, zbuf)
      huff.encode_block(zbuf, prev_dc, bit_writer)
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

    def extract_luminance(width, height)
      luminance = Array.new(width * height)
      if source.respond_to?(:packed_pixels)
        packed = source.packed_pixels
        r_shift, g_shift, b_shift = packed_shifts
        i = 0
        (width * height).times do
          color = packed[i]
          r = (color >> r_shift) & 0xFF
          g = (color >> g_shift) & 0xFF
          b = (color >> b_shift) & 0xFF
          luminance[i] = (0.299 * r + 0.587 * g + 0.114 * b).round.clamp(0, 255)
          i += 1
        end
      else
        height.times do |y|
          row = y * width
          width.times do |x|
            pixel = source[x, y]
            luminance[row + x] = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round.clamp(0, 255)
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
          y_data[i]  = ( 0.299    * r + 0.587    * g + 0.114    * b).round.clamp(0, 255)
          cb_data[i] = (-0.168736 * r - 0.331264 * g + 0.5      * b + 128.0).round.clamp(0, 255)
          cr_data[i] = ( 0.5      * r - 0.418688 * g - 0.081312 * b + 128.0).round.clamp(0, 255)
          i += 1
        end
      else
        height.times do |py|
          row = py * width
          width.times do |px|
            pixel = source[px, py]
            r = pixel.r; g = pixel.g; b = pixel.b
            i = row + px
            y_data[i]  = ( 0.299    * r + 0.587    * g + 0.114    * b).round.clamp(0, 255)
            cb_data[i] = (-0.168736 * r - 0.331264 * g + 0.5      * b + 128.0).round.clamp(0, 255)
            cr_data[i] = ( 0.5      * r - 0.418688 * g - 0.081312 * b + 128.0).round.clamp(0, 255)
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
        src_row = sy * width
        row8 = row << 3
        8.times do |col|
          sx = bx + col
          sx = max_x if sx > max_x
          block[row8 | col] = channel[src_row + sx] - 128.0
        end
      end
      block
    end
  end
end
