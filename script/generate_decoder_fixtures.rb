# frozen_string_literal: true

# Development-only: requires libjpeg-turbo cjpeg/djpeg on PATH. The test suite
# uses the checked-in JPEGs and RGB hashes without any external tools.
require "open3"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

destination = File.expand_path("../test/fixtures/decoder", __dir__)
FileUtils.mkdir_p(destination)
manifest = {}
run = lambda do |*args|
  out, err, status = Open3.capture3(*args)
  abort "#{args.inspect}: #{err}" unless status.success?
  out.b
end

Dir.mktmpdir("pure-jpeg-fixtures") do |dir|
  make = lambda do |name, width, height, options, supported = true|
    pixels = height.times.flat_map do |y|
      width.times.flat_map { |x| [(x * 13 + y * 5) % 256, (y * 17 + x * 3) % 256, (x * 7 + y * 11) % 256] }
    end
    input = File.join(dir, "input.ppm")
    File.binwrite(input, "P6\n#{width} #{height}\n255\n".b + pixels.pack("C*"))
    output = File.join(destination, "#{name}.jpg")
    run.call("cjpeg", "-quality", "85", *options, "-outfile", output, input)
    reference = run.call("djpeg", "-strict", "-dct", "int", "-nosmooth", output)
    header = /\AP([56])\s+\d+\s+\d+\s+255\s/n.match(reference)
    abort "Unexpected reference format" unless header
    rgb = reference.byteslice(header.end(0)..)
    rgb = rgb.bytes.flat_map { |v| [v, v, v] }.pack("C*") if header[1] == "5"
    manifest[name] = { "width" => width, "height" => height,
                       "rgb_sha256" => Digest::SHA256.hexdigest(rgb), "supported" => supported }
  end

  { "420" => "2x2,1x1,1x1", "422" => "2x1,1x1,1x1", "444" => "1x1,1x1,1x1",
    "440" => "1x2,1x1,1x1", "411" => "4x1,1x1,1x1", "gray" => nil }.each do |sampling, factors|
    options = factors ? ["-sample", factors] : ["-grayscale"]
    make.call("edge-#{sampling}", 17, 17, options + ["-progressive"])
    make.call("restart-#{sampling}", 32, 32, options + ["-progressive", "-restart", "1"])
  end
  make.call("tiny", 1, 1, ["-progressive"])
  make.call("baseline-restart", 32, 32, ["-restart", "2B"])
  make.call("luma-subsampled", 32, 32, ["-sample", "1x1,2x2,1x1"])
  make.call("rgb", 16, 16, ["-rgb"], false)
  scans = File.join(dir, "sequential.scans")
  File.write(scans, "0;\n1;\n2;\n")
  make.call("sequential-multiscan", 32, 32, ["-scans", scans])
  make.call("sequential-edge-restart", 17, 23, ["-scans", scans, "-restart", "1"])
  File.write(scans, "0,1;\n2;\n")
  make.call("mixed-scan-restart", 17, 17, ["-scans", scans, "-restart", "2B"])
end
File.write(File.join(destination, "manifest.json"), JSON.pretty_generate(manifest) + "\n")
puts "Generated #{manifest.size} decoder fixtures"
