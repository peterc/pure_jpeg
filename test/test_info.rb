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
    path = fixture_path("a-progressive.jpg")

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

  def test_info_returns_nil_icc_profile_when_absent
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85).to_bytes

    info = PureJPEG.info(data)

    assert_nil info.icc_profile
  end

  def test_info_extracts_icc_profile
    source = gradient_source(8, 8)
    data = PureJPEG.encode(source, quality: 85).to_bytes
    profile_data = "fake-icc-profile-data-for-testing"
    data_with_icc = inject_icc_profile(data, profile_data)

    info = PureJPEG.info(data_with_icc)

    assert_equal profile_data, info.icc_profile
  end

  private

  def inject_icc_profile(jpeg_data, profile_data)
    # Insert a single APP2 ICC_PROFILE chunk right after SOI
    sig = "ICC_PROFILE\0".b
    seq = 1.chr.b
    total = 1.chr.b
    payload = sig + seq + total + profile_data.b
    length = [payload.bytesize + 2].pack("n")
    app2 = "\xFF\xE2".b + length + payload

    jpeg_data[0, 2] + app2 + jpeg_data[2..]
  end
end
