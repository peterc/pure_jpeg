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
        @image = image
        @width = image.width
        @height = image.height
      end

      # Retrieve a pixel at the given coordinate.
      #
      # @param x [Integer] column (0-based)
      # @param y [Integer] row (0-based)
      # @return [Pixel]
      def [](x, y)
        color = @image[x, y]
        Pixel.new(
          ChunkyPNG::Color.r(color),
          ChunkyPNG::Color.g(color),
          ChunkyPNG::Color.b(color)
        )
      end
    end
  end
end
