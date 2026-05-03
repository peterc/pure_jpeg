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
      # @param background [Array<Integer>, nil] optional [r, g, b] background
      #   color to composite transparent pixels against before encoding
      def initialize(image, background: nil)
        @width = image.width
        @height = image.height
        @packed_pixels = if background.nil?
                           image.pixels
                         else
                           composite_pixels(image.pixels, background)
                         end
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

      private

      def composite_pixels(pixels, background)
        bg_r, bg_g, bg_b = validate_background!(background)

        pixels.map do |color|
          alpha = color & 0xFF
          next color if alpha == 255

          src_r = (color >> 24) & 0xFF
          src_g = (color >> 16) & 0xFF
          src_b = (color >> 8) & 0xFF
          inv_alpha = 255 - alpha

          r = ((src_r * alpha) + (bg_r * inv_alpha) + 127) / 255
          g = ((src_g * alpha) + (bg_g * inv_alpha) + 127) / 255
          b = ((src_b * alpha) + (bg_b * inv_alpha) + 127) / 255

          (r << 24) | (g << 16) | (b << 8) | 255
        end
      end

      def validate_background!(background)
        unless background.respond_to?(:length) && background.length == 3 &&
               background.all? { |v| v.is_a?(Integer) && v.between?(0, 255) }
          raise ArgumentError, "background must be an [r, g, b] array of integers between 0 and 255"
        end

        background
      end
    end
  end
end
