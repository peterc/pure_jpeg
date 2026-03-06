# frozen_string_literal: true

module PureJPEG
  module Source
    # Pixel source adapter for +ChunkyPNG::Image+.
    #
    # Wraps a +ChunkyPNG::Image+ so it can be passed directly to
    # {PureJPEG.encode}. Requires the +chunky_png+ gem.
    #
    # @example
    #   image = ChunkyPNG::Image.from_file("photo.png")
    #   source = PureJPEG::Source::ChunkyPNGSource.new(image)
    #   PureJPEG.encode(source).write("photo.jpg")
    class ChunkyPNGSource
      # @return [Integer] image width in pixels
      attr_reader :width
      # @return [Integer] image height in pixels
      attr_reader :height

      # @param image [ChunkyPNG::Image] the source PNG image
      def initialize(image)
        @width = image.width
        @height = image.height
        @packed_pixels = image.pixels
      end

      # @return [Array<Integer>] flat row-major array of packed RGBA integers
      attr_reader :packed_pixels

      # Retrieve a pixel at the given coordinate.
      #
      # @param x [Integer] column (0-based)
      # @param y [Integer] row (0-based)
      # @return [Pixel]
      def [](x, y)
        color = @packed_pixels[y * @width + x]
        Pixel.new(
          (color >> 24) & 0xFF,
          (color >> 16) & 0xFF,
          (color >> 8) & 0xFF
        )
      end
    end
  end
end
