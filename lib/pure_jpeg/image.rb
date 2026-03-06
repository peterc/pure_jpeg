# frozen_string_literal: true

module PureJPEG
  # A decoded JPEG image with pixel-level access.
  #
  # Internally stores pixels as packed integers (+r << 16 | g << 8 | b+) to
  # avoid per-pixel object allocation. Implements the same pixel source
  # interface (+width+, +height+, +[x, y]+) as encoder inputs, so a decoded
  # image can be passed directly to {PureJPEG.encode} for re-encoding.
  class Image
    # @return [Integer] image width in pixels
    attr_reader :width
    # @return [Integer] image height in pixels
    attr_reader :height

    # @return [Array<Integer>] flat row-major array of packed RGB integers.
    #   Format: +(r << 16) | (g << 8) | b+.
    attr_reader :packed_pixels

    # @param width [Integer]
    # @param height [Integer]
    # @param packed_pixels [Array<Integer>] flat row-major array of packed RGB
    #   integers in the format +(r << 16) | (g << 8) | b+
    def initialize(width, height, packed_pixels)
      @width = width
      @height = height
      @packed_pixels = packed_pixels
    end

    # Retrieve a pixel by coordinate.
    #
    # @param x [Integer] column (0-based)
    # @param y [Integer] row (0-based)
    # @return [Source::Pixel] pixel with +.r+, +.g+, +.b+ in 0-255
    def [](x, y)
      color = @packed_pixels[y * @width + x]
      Source::Pixel.new((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    end

    # Set a pixel by coordinate.
    #
    # @param x [Integer] column (0-based)
    # @param y [Integer] row (0-based)
    # @param pixel [Source::Pixel] replacement pixel
    # @return [Source::Pixel]
    def []=(x, y, pixel)
      @packed_pixels[y * @width + x] = (pixel.r << 16) | (pixel.g << 8) | pixel.b
      pixel
    end

    # Iterate over every pixel in the image.
    #
    # @yieldparam x [Integer] column
    # @yieldparam y [Integer] row
    # @yieldparam pixel [Source::Pixel] the pixel at (x, y)
    # @return [void]
    def each_pixel
      @height.times do |y|
        @width.times do |x|
          yield x, y, self[x, y]
        end
      end
    end

    # Iterate over every pixel without allocating Pixel structs.
    #
    # @yieldparam x [Integer] column
    # @yieldparam y [Integer] row
    # @yieldparam r [Integer] red component (0-255)
    # @yieldparam g [Integer] green component (0-255)
    # @yieldparam b [Integer] blue component (0-255)
    # @return [void]
    def each_rgb
      i = 0
      @height.times do |y|
        @width.times do |x|
          color = @packed_pixels[i]
          yield x, y, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF
          i += 1
        end
      end
    end
  end
end
