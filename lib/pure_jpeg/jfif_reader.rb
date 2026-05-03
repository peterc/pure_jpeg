# frozen_string_literal: true

module PureJPEG
  class JFIFReader
    attr_reader :width, :height, :components, :quant_tables, :huffman_tables,
                :restart_interval, :progressive, :scans, :icc_profile

    Component = Struct.new(:id, :h_sampling, :v_sampling, :qt_id)
    ScanComponent = Struct.new(:id, :dc_table_id, :ac_table_id)
    Scan = Struct.new(:components, :spectral_start, :spectral_end, :successive_high, :successive_low, :data, :huffman_tables)

    def initialize(data, stop_after_frame: false)
      @data = data.b
      @stop_after_frame = stop_after_frame
      @pos = 0
      @quant_tables = {}
      @huffman_tables = {}
      @components = []
      @restart_interval = 0
      @progressive = false
      @scans = []
      @icc_chunks = {}
      parse
      assemble_icc_profile
    end

    def scan_components
      @scans.first&.components || []
    end

    def scan_data
      @scans.first&.data || "".b
    end

    private

    def parse
      expect_marker(0xD8) # SOI

      loop do
        marker = read_marker
        case marker
        when 0xE2 # APP2 (may contain ICC profile)
          parse_app2
        when 0xE0, 0xE1, 0xE3..0xEF # APP0, APP1, APP3-APP15
          skip_segment
        when 0xDB # DQT
          parse_dqt
        when 0xC4 # DHT
          parse_dht
        when 0xC0 # SOF0 (baseline)
          parse_sof0
          return if @stop_after_frame
        when 0xC2 # SOF2 (progressive)
          parse_sof0
          @progressive = true
          return if @stop_after_frame
        when 0xDA # SOS
          scan = parse_sos
          scan.data = extract_scan_data
          scan.huffman_tables = @huffman_tables.dup
          @scans << scan
          return unless @progressive
        when 0xFE # COM (comment)
          skip_segment
        when 0xDD # DRI (restart interval)
          parse_dri
        when 0xD9 # EOI
          return
        else
          skip_segment
        end
      end
    end

    def read_byte
      raise PureJPEG::DecodeError, "Unexpected end of JPEG data" if @pos >= @data.bytesize
      byte = @data.getbyte(@pos)
      @pos += 1
      byte
    end

    def read_u16
      (read_byte << 8) | read_byte
    end

    def read_marker
      byte = read_byte
      raise PureJPEG::DecodeError, "Expected 0xFF, got 0x#{byte.to_s(16)}" unless byte == 0xFF
      # Skip padding 0xFF bytes
      code = read_byte
      code = read_byte while code == 0xFF
      code
    end

    def expect_marker(expected)
      marker = read_marker
      raise PureJPEG::DecodeError, "Expected marker 0x#{expected.to_s(16)}, got 0x#{marker.to_s(16)}" unless marker == expected
    end

    ICC_PROFILE_SIG = "ICC_PROFILE\0".b

    def parse_app2
      end_pos = read_segment_end

      if (end_pos - @pos) >= 14 && @data[@pos, 12] == ICC_PROFILE_SIG
        @pos += 12
        seq_no = read_byte
        _total = read_byte
        @icc_chunks[seq_no] = @data[@pos, end_pos - @pos]
      end

      @pos = end_pos
    end

    def assemble_icc_profile
      return if @icc_chunks.empty?

      @icc_profile = @icc_chunks.sort_by(&:first).map(&:last).join.b
    end

    def skip_segment
      @pos = read_segment_end
    end

    def parse_dqt
      end_pos = read_segment_end

      while @pos < end_pos
        info = read_byte
        precision = (info >> 4) & 0x0F  # 0 = 8-bit, 1 = 16-bit
        table_id = info & 0x0F
        bytes_per_value = precision == 0 ? 1 : 2
        ensure_remaining_in_segment!(end_pos, 64 * bytes_per_value, "DQT")

        zigzag_table = Array.new(64)
        64.times do |i|
          zigzag_table[i] = precision == 0 ? read_byte : read_u16
        end
        # DQT stores values in zigzag order; convert to raster order
        table = Array.new(64)
        64.times { |i| table[Zigzag::ORDER[i]] = zigzag_table[i] }
        @quant_tables[table_id] = table
      end
    end

    def parse_dht
      end_pos = read_segment_end

      while @pos < end_pos
        ensure_remaining_in_segment!(end_pos, 17, "DHT")
        info = read_byte
        table_class = (info >> 4) & 0x0F  # 0 = DC, 1 = AC
        table_id = info & 0x0F

        bits = Array.new(16) { read_byte }
        total = bits.sum
        ensure_remaining_in_segment!(end_pos, total, "DHT")
        values = Array.new(total) { read_byte }

        @huffman_tables[[table_class, table_id]] = { bits: bits, values: values }
      end
    end

    def parse_sof0
      end_pos = read_segment_end
      ensure_remaining_in_segment!(end_pos, 6, "SOF")
      read_byte # precision (always 8 for baseline)
      @height = read_u16
      @width = read_u16
      num_components = read_byte
      ensure_remaining_in_segment!(end_pos, num_components * 3, "SOF")

      @components = Array.new(num_components) do
        id = read_byte
        sampling = read_byte
        h = (sampling >> 4) & 0x0F
        v = sampling & 0x0F
        qt_id = read_byte
        Component.new(id, h, v, qt_id)
      end
      @pos = end_pos
    end

    def parse_sos
      end_pos = read_segment_end
      ensure_remaining_in_segment!(end_pos, 1, "SOS")
      num_components = read_byte
      ensure_remaining_in_segment!(end_pos, num_components * 2 + 3, "SOS")

      components = Array.new(num_components) do
        id = read_byte
        tables = read_byte
        dc_id = (tables >> 4) & 0x0F
        ac_id = tables & 0x0F
        ScanComponent.new(id, dc_id, ac_id)
      end

      ss = read_byte  # spectral selection start
      se = read_byte  # spectral selection end
      ahl = read_byte # successive approximation
      ah = (ahl >> 4) & 0x0F
      al = ahl & 0x0F
      @pos = end_pos
      Scan.new(components, ss, se, ah, al, nil)
    end

    def parse_dri
      end_pos = read_segment_end
      ensure_remaining_in_segment!(end_pos, 2, "DRI")
      @restart_interval = read_u16
      @pos = end_pos
    end

    def read_segment_end
      length = read_u16
      raise PureJPEG::DecodeError, "Invalid JPEG segment length: #{length}" if length < 2

      end_pos = @pos + length - 2
      if end_pos > @data.bytesize
        raise PureJPEG::DecodeError, "JPEG segment length exceeds available data"
      end

      end_pos
    end

    def ensure_remaining_in_segment!(end_pos, byte_count, segment_name)
      return if @pos + byte_count <= end_pos

      raise PureJPEG::DecodeError, "Truncated #{segment_name} segment"
    end

    # Extract entropy-coded scan data (everything from current position to EOI marker).
    def extract_scan_data
      start = @pos
      len = @data.bytesize
      # Scan forward looking for a marker that isn't a stuffing byte or restart
      while @pos < len - 1
        found = @data.index("\xFF".b, @pos)
        break unless found && found < len - 1
        @pos = found
        next_byte = @data.getbyte(@pos + 1)
        # 0x00 is byte stuffing, 0xD0-0xD7 are restart markers, 0xFF is padding — all part of scan data
        if next_byte != 0x00 && !(next_byte >= 0xD0 && next_byte <= 0xD7) && next_byte != 0xFF
          break
        end
        @pos += 2
      end
      @data[start...@pos]
    end
  end
end
