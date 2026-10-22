# frozen_string_literal: true

require_relative "test_helper"

class TestMetadataValidation < Minitest::Test
  include TestHelper

  def setup
    @data = PureJPEG.encode(gradient_source(8, 8)).to_bytes
  end

  def icc(sequence, total, payload)
    payload = "ICC_PROFILE\0".b + [sequence, total].pack("CC") + payload.b
    "\xff\xe2".b + [payload.bytesize + 2].pack("n") + payload
  end

  def with_headers(headers)
    @data[0...2] + headers + @data[2..]
  end

  def test_metadata_finds_icc_after_frame_without_reading_scan
    sos = @data.index("\xff\xda".b)
    data = @data[0...sos] + icc(1, 1, "profile") + @data[sos..]
    assert_equal "profile", PureJPEG.info(data).icc_profile
    assert_equal "profile", PureJPEG.read(data).icc_profile
    assert_equal "profile", PureJPEG.info(data[0...(sos + icc(1, 1, "profile").bytesize + 2)]).icc_profile
  end

  def test_complete_out_of_order_icc_chunks
    data = with_headers(icc(2, 2, "second") + icc(1, 2, "first"))
    assert_equal "firstsecond", PureJPEG.info(data).icc_profile
    assert_equal "firstsecond", PureJPEG.read(data).icc_profile
  end

  def test_incomplete_or_invalid_icc_is_ignored
    [icc(1, 2, "partial"), icc(0, 1, "zero"), icc(2, 1, "bad index"),
     icc(1, 1, "a") + icc(1, 1, "duplicate"),
     icc(1, 2, "a") + icc(2, 3, "inconsistent")].each do |headers|
      data = with_headers(headers)
      assert_nil PureJPEG.info(data).icc_profile
      assert_nil PureJPEG.read(data).icc_profile
    end
  end

  def test_metadata_still_accepts_frame_only_input
    sof = @data.index("\xff\xc0".b)
    frame_end = sof + 2 + @data[sof + 2, 2].unpack1("n")
    info = PureJPEG.info(@data[0...frame_end])
    assert_equal [8, 8, 3], [info.width, info.height, info.component_count]
  end
end
