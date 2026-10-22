These small JPEGs are generated from a deterministic synthetic RGB pattern by
script/generate_decoder_fixtures.rb, using libjpeg-turbo cjpeg and djpeg.
Initial generation used libjpeg-turbo 3.2.0 (build 20260630).

manifest.json records dimensions and SHA-256 digests of the reference decoded
RGB byte stream (three bytes per pixel, row-major). Reference decoding uses
accurate integer IDCT and nearest-neighbor upsampling: djpeg -dct int -nosmooth.
This matches PureJPEG's rendering choices. The RGB JPEG is deliberately marked
unsupported; the other fixtures must match the reference pixels exactly.

Regenerate from the repository root:
  ruby script/generate_decoder_fixtures.rb

Inspect any changed hashes rather than updating them to match PureJPEG. Normal
tests require only these checked-in files and Ruby's standard library, not
libjpeg-turbo or any other native dependency.
