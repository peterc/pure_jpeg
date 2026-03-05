# Creative encoding with PureJPEG

PureJPEG exposes access to several 'knobs' to manipulate the JPEG encoding pipeline. These produce a range of aesthetic effects by controlling how the DCT frequency coefficients are quantized.

All examples assume:

```ruby
require "chunky_png"
require_relative "lib/pure_jpeg"

image = ChunkyPNG::Image.from_file("input.png")
source = PureJPEG::Source::ChunkyPNGSource.new(image)
```

## Scrambled quantization ("early digicam" look)

The JPEG spec stores quantization tables in zigzag order. Enabling `scramble_quantization` writes them in raster order instead, which means any standard viewer applies the wrong quantization values to the wrong frequency coefficients. The result is a chaotic, crunchy artifact pattern reminiscent of early 2000s digital cameras (what I really wanted in the first place).

```ruby
PureJPEG.encode(source, quality: 20, scramble_quantization: true).write("scrambled.jpg")
```

Lower quality values amplify the effect.

## Chroma crush (sharp detail, broken color)

Set high luminance quality but aggressively compress the chrominance channels. Detail and edges stay sharp but the color information collapses into large blocky patches with hue shifts.

```ruby
PureJPEG.encode(source, quality: 90, chroma_quality: 5).write("chromacrush.jpg")
```

## Luma crush (soft image, faithful color)

The opposite: crush the luminance channel while preserving chrominance. Produces a soft, almost oil-painting quality where the image is blocky and low-detail but the colors remain surprisingly accurate.

```ruby
PureJPEG.encode(source, quality: 10, chroma_quality: 95).write("lumacrush.jpg")
```

## DC-only (8x8 mosaic)

A custom quantization table that preserves only the DC coefficient (the average brightness of each 8x8 block) and kills all 63 AC coefficients. Every block becomes a single flat color, producing a hard mosaic effect.

```ruby
dc_only = [1] + [255] * 63
PureJPEG.encode(source, luminance_table: dc_only, chrominance_table: dc_only).write("dconly.jpg")
```

You can soften the mosaic by letting a few low-frequency AC coefficients through:

```ruby
# Keep DC and the first few AC coefficients
gentle_mosaic = [1, 1, 1, 2, 4, 8] + [255] * 58
PureJPEG.encode(source, luminance_table: gentle_mosaic, chrominance_table: gentle_mosaic).write("gentle_mosaic.jpg")
```

## Inverted frequency emphasis

Normally JPEG preserves low frequencies (smooth gradients) and discards high frequencies (fine detail). This modifier inverts that, preserving edges and texture while crushing smooth areas. The result is an embossed or etched look.

```ruby
inverter = ->(table, _channel) {
  max = table.max
  table.map { |v| [max + 1 - v, 1].max }
}
PureJPEG.encode(source, quality: 30, quantization_modifier: inverter).write("inverted.jpg")
```

## Combining effects

The `quantization_modifier` proc receives the table and a channel identifier (`:luminance` or `:chrominance`), so you can apply different transformations per channel:

```ruby
modifier = ->(table, channel) {
  case channel
  when :luminance
    # Sharpen luma by halving quantization values
    table.map { |v| [v / 2, 1].max }
  when :chrominance
    # Posterize color by doubling quantization values
    table.map { |v| [v * 2, 255].min }
  end
}
PureJPEG.encode(source, quality: 50, quantization_modifier: modifier).write("combined.jpg")
```

## Full option reference

```ruby
PureJPEG.encode(source,
  quality: 85,                    # 1-100, overall compression level
  grayscale: false,               # encode as single-channel grayscale
  chroma_quality: nil,            # 1-100, independent Cb/Cr quality (defaults to quality)
  luminance_table: nil,           # custom 64-element quantization table for Y (raster order)
  chrominance_table: nil,         # custom 64-element quantization table for Cb/Cr (raster order)
  quantization_modifier: nil,     # proc(table, :luminance/:chrominance) -> modified table
  scramble_quantization: false    # write quant tables in wrong order (digicam effect)
)
```
