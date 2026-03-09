# frozen_string_literal: true

require_relative "test_helper"

class TestInfo < Minitest::Test
  include TestHelper

  def test_info_from_bytes
    source = gradient_source(32, 24)
    data = PureJPEG.encode(source, quality: 85).to_bytes

    info = PureJPEG.info(data)

    assert_equal 32, info.width
    assert_equal 24, info.height
    assert_equal 3, info.component_count
    refute info.progressive
  end

  def test_info_from_progressive_file
    path = File.expand_path("../examples/a-progressive.jpg", __dir__)

    info = PureJPEG.info(path)

    assert_equal 1024, info.width
    assert_equal 1024, info.height
    assert_equal 3, info.component_count
    assert info.progressive
  end

  def test_info_does_not_require_full_scan_data
    source = gradient_source(16, 16)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    sos_pos = data.index("\xFF\xDA".b)
    refute_nil sos_pos, "Should find SOS marker"

    truncated_after_header = data[0...(sos_pos + 2)]
    info = PureJPEG.info(truncated_after_header)

    assert_equal 16, info.width
    assert_equal 16, info.height
    assert_equal 3, info.component_count
    refute info.progressive
  end

  def test_info_raises_when_frame_header_missing
    assert_raises(PureJPEG::DecodeError) { PureJPEG.info("\xFF\xD8\xFF\xD9".b) }
  end
end
