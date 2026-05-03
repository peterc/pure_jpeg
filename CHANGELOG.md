# Changelog

## 0.3.3

New features:

- `PureJPEG.from_chunky_png` accepts `background: [r, g, b]` to composite transparent PNG pixels before JPEG encoding

Fixes:

- Invalid `quality` and `chroma_quality` values now raise clear `ArgumentError`s
- `Image#[]` and `Image#[]=` now raise `IndexError` for out-of-bounds coordinates
- Hardened JFIF segment length validation for malformed JPEG input

## 0.3.2

Performance:

- Replaced matrix-multiply float DCT with integer-scaled AAN (Arai-Agui-Nakajima) DCT from the IJG reference implementation -- all-integer, no Float allocations
- Fixed-point integer arithmetic for RGB/YCbCr color space conversion in both encoder and decoder
- Eliminated short-lived Array allocations in Huffman encoder (`category_and_bits` split into separate methods)
- `String#<<` with Integer instead of `byte.chr` to avoid String allocations in bit writer
- DCT inner loop unrolling to eliminate nested block invocations
- Unrolled `write_block` and `extract_block_into` inner loops
- Integer rounding division in quantization (no more Float division + round)
- Hoisted hash lookups and method calls out of per-pixel loops in decoder

Result: ~2.9x faster encode, ~4.6x faster decode on Ruby 4.0.2 with YJIT.

Credits: [Ufuk Kayserilioglu](https://github.com/paracycle)

## 0.3.1

Fixes:

- Fixed shared `Pixel` instance bug in decoder that could corrupt pixel data
- Encoder validates return values from `quantization_modifier` blocks

## 0.3.0

New features:

- `PureJPEG.info` for reading dimensions and metadata without full decode
- ICC color profile extraction (available on `Info` and `Image`)
- Optional image-specific optimized Huffman tables (`optimize_huffman: true`)

Fixes:

- Decoder validates Huffman table, quantization table, and component references with clear error messages
- Color decoding looks up Y/Cb/Cr components by ID instead of assuming SOF array order
- Support for non-standard component IDs (e.g. 0, 1, 2 as used by some Adobe tools)
- Explicit error for unsupported component counts (e.g. CMYK)
- Encoder no longer holds file handle open during encoding

## 0.2.0

New features:

- Progressive JPEG decoding (SOF2) with spectral selection and successive approximation
- `Image#each_rgb` for iterating pixels without per-pixel struct allocation
- `PureJPEG::DecodeError` exception class for all decoding errors
- Validation of custom quantization tables (length and value range)

Performance:

- Packed integer pixel storage in `Image` eliminates per-pixel object allocation on decode (~6x faster decode)
- Fast path for encoder pixel extraction from packed sources (`ChunkyPNGSource`, `Image`)
- `BitReader#read_bits` fast path when buffer already has enough bits
- `BitWriter` builds a `String` directly instead of `Array` + `pack`
- `Huffman.build_table` returns an `Array` for O(1) lookup instead of `Hash`
- Faster scan data extraction using `String#index`

Fixes:

- JPEG data detection uses SOI marker check instead of null-byte heuristic
- `RawSource` pixels default to black instead of `nil`
- `BitReader` bounds check for truncated 0xFF sequences
- `JFIFReader` bounds check when reading past end of data
- Fixed dead tautological check in AC encoding EOB logic

## 0.1.0

Initial release.

- Baseline DCT encoder (SOF0, 8-bit, Huffman)
- YCbCr color with 4:2:0 chroma subsampling
- Grayscale mode
- Baseline DCT decoder with support for any chroma subsampling factor and restart markers
- Creative encoding options: independent chroma quality, custom quantization tables, quantization modifier, scrambled quantization
- Pure Ruby, no native dependencies
