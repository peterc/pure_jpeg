# frozen_string_literal: true

# Portable README benchmark, including for AOT compilation with Spinel.
# Encode takes the bundled 1024x1024 PNG's packed RGBA bytes in raster order.
# Decode takes a JPEG. Both load their input before timing.
#
# From the repository root:
#   ruby -rchunky_png -e 'File.binwrite("/tmp/a.rgba", ChunkyPNG::Image.from_file("examples/a.png").pixels.pack("N*"))'
#   ruby --yjit benchmark/runtime_comparison.rb encode /tmp/a.rgba
#   ruby --yjit benchmark/runtime_comparison.rb decode examples/a-progressive.jpg
#   /usr/bin/time -l ruby --yjit benchmark/runtime_comparison.rb decode examples/a.jpg --once
#   spinel benchmark/runtime_comparison.rb -o /tmp/pure-jpeg-bench
#   /tmp/pure-jpeg-bench encode /tmp/a.rgba --verify /tmp/spinel.jpg
#
# The larger memory-only input is a 3264x2448 solid RGB(60, 90, 120) PPM
# encoded by libjpeg-turbo 3.2.0 cjpeg -quality 75 -progressive -sample 1x1,1x1,1x1.
require_relative "../lib/pure_jpeg"

operation, path, mode, output = ARGV
abort "Usage: encode|decode INPUT [--once | --verify OUTPUT]" unless path &&
  %w[encode decode].include?(operation) && [nil, "--once", "--verify"].include?(mode)

PackedPNG = Struct.new(:width, :height, :pixels)
if operation == "encode"
  rgba = File.binread(path)
  abort "Expected 1024x1024 RGBA input" unless rgba.bytesize == 1024 * 1024 * 4
  source = PureJPEG::Source::ChunkyPNGSource.new(PackedPNG.new(1024, 1024, rgba.unpack("N*")))
else
  jpeg = File.binread(path)
end

def run_operation(operation, source, jpeg)
  return PureJPEG.encode(source, quality: 85).to_bytes if operation == "encode"
  PureJPEG.read(jpeg)
end

if mode == "--once"
  run_operation(operation, source, jpeg)
elsif mode == "--verify"
  abort "Supply an output file for --verify" unless output
  result = run_operation(operation, source, jpeg)
  bytes = operation == "encode" ? result : result.packed_pixels.pack("N*")
  File.binwrite(output, bytes)
else
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) - start < 20
    run_operation(operation, source, jpeg)
  end
  samples = Array.new(15) do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run_operation(operation, source, jpeg)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end
  puts samples.sort[7]
end
