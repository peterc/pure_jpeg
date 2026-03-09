# frozen_string_literal: true

module PureJPEG
  # Lightweight metadata returned by {.info}.
  Info = Struct.new(:width, :height, :component_count, :progressive, :icc_profile, keyword_init: true)
end
