# Changelog

## 0.1.0

Initial release.

- Baseline DCT encoder (SOF0, 8-bit, Huffman)
- YCbCr color with 4:2:0 chroma subsampling
- Grayscale mode
- Baseline DCT decoder with support for any chroma subsampling factor and restart markers
- Creative encoding options: independent chroma quality, custom quantization tables, quantization modifier, scrambled quantization
- Pure Ruby, no native dependencies
