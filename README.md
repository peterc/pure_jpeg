# PureJPEG

Pure Ruby JPEG encoder and decoder. Implements baseline JPEG (DCT, Huffman, 4:2:0 chroma subsampling) and exposes a variety of encoding options to adjust parts of the JPEG pipeline not normally available (I needed this to recreate the JPEG compression styles of older digital cameras - don't ask..)

## Installation

You know the drill: 

```ruby
gem "pure_jpeg"
```

```
gem install pure_jpeg
```

There are no runtime dependencies. [ChunkyPNG](https://github.com/wvanbergen/chunky_png) is optional and for if you want to use `from_chunky_png`. I have a pure PNG encoder/decoder not far behind this that will ultimately plug in nicely too to get pure Ruby graphical bliss ;-)

`examples/` contains some useful example scripts for basic JPEG to PNG and PNG to JPEG conversion if you want to do some quick tests without writing code.

## Encoding (making JPEGs!)

### From ChunkyPNG (easiest to get started)

```ruby
require "chunky_png"
require "pure_jpeg"

image = ChunkyPNG::Image.from_file("photo.png")
PureJPEG.from_chunky_png(image, quality: 80).write("photo.jpg")
```

### From any pixel source

PureJPEG accepts any object that responds to `width`, `height`, and `[x, y]` (returning an object with `.r`, `.g`, `.b` in 0-255):

```ruby
require "pure_jpeg"

encoder = PureJPEG.encode(source, quality: 85)
encoder.write("output.jpg")

# Or get raw bytes
jpeg_data = encoder.to_bytes
```

### From raw pixel data

```ruby
source = PureJPEG::Source::RawSource.new(width, height) do |x, y|
  [r, g, b]  # return RGB values 0-255
end

PureJPEG.encode(source).write("output.jpg")
```

### Grayscale

```ruby
PureJPEG.encode(source, grayscale: true).write("gray.jpg")
```

### Encoder options

```ruby
PureJPEG.encode(source,
  quality: 85,                    # 1-100, overall compression level
  grayscale: false,               # single-channel grayscale mode
  chroma_quality: nil,            # 1-100, independent Cb/Cr quality (defaults to quality)
  luminance_table: nil,           # custom 64-element quantization table for Y
  chrominance_table: nil,         # custom 64-element quantization table for Cb/Cr
  quantization_modifier: nil,     # proc(table, :luminance/:chrominance) -> modified table
  scramble_quantization: false    # intentionally misordered quant tables (creative effect)
)
```

See [CREATIVE.md](CREATIVE.md) for detailed examples of the creative encoding options.

Each stage of the JPEG pipeline is a separate module, so individual components (DCT, quantization, Huffman coding) can be replaced or extended independently which is kinda my plan here as I made this to play around with effects.

## Decoding (reading JPEGs!)

### From file

```ruby
image = PureJPEG.read("photo.jpg")
image.width   # => 1024
image.height  # => 768
pixel = image[100, 200]
pixel.r  # => 182
pixel.g  # => 140
pixel.b  # => 97
```

### From binary data

```ruby
image = PureJPEG.read(jpeg_bytes)
```

### Iterating pixels

```ruby
image.each_pixel do |x, y, pixel|
  puts "#{x},#{y}: rgb(#{pixel.r}, #{pixel.g}, #{pixel.b})"
end
```

### Re-encoding

A decoded `PureJPEG::Image` implements the same pixel source interface, so it can be passed directly back to the encoder:

```ruby
image = PureJPEG.read("input.jpg")
PureJPEG.encode(image, quality: 60).write("recompressed.jpg")
```

### Converting to PNG (with ChunkyPNG)

```ruby
image = PureJPEG.read("photo.jpg")

png = ChunkyPNG::Image.new(image.width, image.height)
image.each_pixel do |x, y, pixel|
  png[x, y] = ChunkyPNG::Color.rgb(pixel.r, pixel.g, pixel.b)
end
png.save("photo.png")
```

## Format support

Encoding:
- Baseline DCT (SOF0)
- 8-bit precision
- Grayscale (1 component) and YCbCr color (3 components)
- 4:2:0 chroma subsampling (color) or no subsampling (grayscale)
- Standard Huffman tables (Annex K)

Decoding:
- Baseline DCT (SOF0)
- 8-bit precision
- 1-component (grayscale) and 3-component (YCbCr) images
- Any chroma subsampling factor (4:4:4, 4:2:2, 4:2:0, etc.)
- Restart markers (DRI/RST)

Not supported: progressive JPEG (SOF2), arithmetic coding, 12-bit precision, multi-scan, EXIF/ICC profile preservation. Largely because I don't need these, but they are all do-able, especially with how loosely coupled this library is internally. Raise an issue if you really care about them!

## Performance

On a 1024x1024 image (Ruby 3.4 on my M1 Max):

| Operation | Time |
|-----------|------|
| Encode (color, q85) | ~2.8s |
| Decode (color) | ~12s |

The encoder uses a separable DCT with a precomputed cosine matrix and reuses all per-block buffers to minimize GC pressure (more on the optimizations below).

## Some useful `rake` tasks

```
bundle install
rake test        # run the test suite
rake benchmark   # benchmark encoding (3 runs against examples/a.png)
rake profile     # CPU profile with StackProf (requires the stackprof gem)
```

## AI Disclosure

Claude Code did the majority of the work. However, it did require a lot of guidance as it was quite naive in its approach at first with its JPEG outputs looking very akin to those of my Kodak digital camera from 2001! It turns out it got something wrong which, amusingly, it seems devices of those era also got wrong (specifically not using the zigzag approach during quanitization).

The initial implementation was also VERY SLOW. It took about 15 seconds just to turn a 1024x1024 PNG into a JPEG, so some profiling was necessary which ended up finding a lot of possible optimizations to make it about 6x faster.

The tests were also a bit superficial, so I worked on getting them beefed up to tackle a variety of edge cases, although they could still be better. It also didn't do RDoc comments, use Minitest, and a variety of other things I had to coerce it into finishing.

I have read all of the code produced. A lot of the internals are above my paygrade but I'm generally OK with what has been produced and fixed a variety of stylistic things along the way.

## License

MIT
