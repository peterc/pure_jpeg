# frozen_string_literal: true

require "stringio"

require_relative "pure_jpeg/version"
require_relative "pure_jpeg/source/interface"
require_relative "pure_jpeg/source/chunky_png_source"
require_relative "pure_jpeg/source/raw_source"
require_relative "pure_jpeg/dct"
require_relative "pure_jpeg/quantization"
require_relative "pure_jpeg/zigzag"
require_relative "pure_jpeg/bit_writer"
require_relative "pure_jpeg/bit_reader"
require_relative "pure_jpeg/huffman/tables"
require_relative "pure_jpeg/huffman/encoder"
require_relative "pure_jpeg/huffman/decoder"
require_relative "pure_jpeg/jfif_writer"
require_relative "pure_jpeg/jfif_reader"
require_relative "pure_jpeg/info"
require_relative "pure_jpeg/image"
require_relative "pure_jpeg/encoder"
require_relative "pure_jpeg/decoder"

  # Pure Ruby JPEG encoder and decoder with no native dependencies.
  #
  # Supports baseline DCT (SOF0) with 8-bit precision, grayscale and YCbCr
  # color (4:2:0 chroma subsampling), and standard Huffman tables (Annex K).
module PureJPEG
  # Raised when decoding invalid or unsupported JPEG data.
  class DecodeError < StandardError; end

  # Maximum image dimension (width or height) allowed for encoding and decoding.
  MAX_DIMENSION = 8192

  # Encode a pixel source as a JPEG.
  #
  # @param source [#width, #height, #[]] any object responding to +width+,
  #   +height+, and +[x, y]+ (returning an object with +.r+, +.g+, +.b+ in 0-255)
  # @param opts [Hash] encoding options passed to {Encoder#initialize}
  # @return [Encoder] an encoder whose output can be retrieved with
  #   {Encoder#write} or {Encoder#to_bytes}
  # @see Encoder#initialize for available options
  def self.encode(source, **opts)
    Encoder.new(source, **opts)
  end

  # Encode a ChunkyPNG::Image as a JPEG.
  #
  # Convenience wrapper that adapts a +ChunkyPNG::Image+ into a pixel source
  # and passes it to {.encode}.
  #
  # @param image [ChunkyPNG::Image] the source image
  # @param opts [Hash] encoding options passed to {Encoder#initialize}
  # @return [Encoder]
  def self.from_chunky_png(image, **opts)
    source = Source::ChunkyPNGSource.new(image)
    Encoder.new(source, **opts)
  end

  # Decode a JPEG from a file path or binary string.
  #
  # @param path_or_data [String] a file path or raw JPEG bytes
  # @return [Image] decoded image with pixel access
  def self.read(path_or_data)
    Decoder.decode(path_or_data)
  end

  # Read JPEG dimensions and basic frame metadata without decoding scan data.
  #
  # @param path_or_data [String] a file path or raw JPEG bytes
  # @return [Info] image metadata parsed from the frame header
  def self.info(path_or_data)
    data = if path_or_data.is_a?(String) && !path_or_data.start_with?("\xFF\xD8".b) && File.exist?(path_or_data)
             File.binread(path_or_data)
           else
             path_or_data.b
           end

    jfif = JFIFReader.new(data, stop_after_frame: true)
    raise DecodeError, "JPEG frame header not found" unless jfif.width && jfif.height

    Info.new(
      width: jfif.width,
      height: jfif.height,
      component_count: jfif.components.length,
      progressive: jfif.progressive
    )
  end
end
