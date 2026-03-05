# frozen_string_literal: true

module PureJPEG
  module Source
    # An in-memory pixel source backed by a flat array.
    #
    # Pixels can be populated via a block at construction time or set
    # individually with {#set}.
    #
    # @example From a block
    #   source = RawSource.new(256, 256) { |x, y| [x, y, 128] }
    #
    # @example Setting pixels individually
    #   source = RawSource.new(256, 256)
    #   source.set(0, 0, 255, 0, 0)
    class RawSource
      # @return [Integer] image width in pixels
      attr_reader :width
      # @return [Integer] image height in pixels
      attr_reader :height

      # @param width [Integer] image width
      # @param height [Integer] image height
      # @yieldparam x [Integer] column
      # @yieldparam y [Integer] row
      # @yieldreturn [Array<Integer>] +[r, g, b]+ values, each 0-255
      def initialize(width, height, &block)
        @width = width
        @height = height
        @pixels = Array.new(width * height)

        if block
          height.times do |y|
            width.times do |x|
              r, g, b = block.call(x, y)
              @pixels[y * width + x] = Pixel.new(r, g, b)
            end
          end
        end
      end

      # Set a pixel at the given coordinate.
      #
      # @param x [Integer] column (0-based)
      # @param y [Integer] row (0-based)
      # @param r [Integer] red (0-255)
      # @param g [Integer] green (0-255)
      # @param b [Integer] blue (0-255)
      # @return [Pixel]
      def set(x, y, r, g, b)
        @pixels[y * @width + x] = Pixel.new(r, g, b)
      end

      # Retrieve a pixel at the given coordinate.
      #
      # @param x [Integer] column (0-based)
      # @param y [Integer] row (0-based)
      # @return [Pixel, nil] the pixel, or +nil+ if not yet set
      def [](x, y)
        @pixels[y * @width + x]
      end
    end
  end
end
