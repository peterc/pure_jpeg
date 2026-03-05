# frozen_string_literal: true

module PureJPEG
  module Source
    # A pixel source is any object responding to:
    #
    # - +width+ -> +Integer+
    # - +height+ -> +Integer+
    # - +[x, y]+ -> an object responding to +.r+, +.g+, +.b+ (each 0-255)

    # An RGB pixel value.
    #
    # @!attribute r [rw]
    #   @return [Integer] red component (0-255)
    # @!attribute g [rw]
    #   @return [Integer] green component (0-255)
    # @!attribute b [rw]
    #   @return [Integer] blue component (0-255)
    Pixel = Struct.new(:r, :g, :b)
  end
end
