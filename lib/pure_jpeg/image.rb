# frozen_string_literal: true

module PureJPEG
  # A decoded JPEG image with pixel-level access.
  #
  # Implements the same pixel source interface (+width+, +height+, +[x, y]+)
  # as encoder inputs, so a decoded image can be passed directly to
  # {PureJPEG.encode} for re-encoding.
  class Image
    # @return [Integer] image width in pixels
    attr_reader :width
    # @return [Integer] image height in pixels
    attr_reader :height

    # @param width [Integer]
    # @param height [Integer]
    # @param pixels [Array<Source::Pixel>] flat row-major array of pixels
    def initialize(width, height, pixels)
      @width = width
      @height = height
      @pixels = pixels
    end

    # Retrieve a pixel by coordinate.
    #
    # @param x [Integer] column (0-based)
    # @param y [Integer] row (0-based)
    # @return [Source::Pixel] pixel with +.r+, +.g+, +.b+ in 0-255
    def [](x, y)
      @pixels[y * @width + x]
    end

    # Set a pixel by coordinate.
    #
    # @param x [Integer] column (0-based)
    # @param y [Integer] row (0-based)
    # @param pixel [Source::Pixel] replacement pixel
    # @return [Source::Pixel]
    def []=(x, y, pixel)
      @pixels[y * @width + x] = pixel
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
  end
end
