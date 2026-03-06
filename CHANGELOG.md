# Changelog

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
