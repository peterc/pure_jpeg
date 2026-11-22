# frozen_string_literal: true

# Measure an entire decode in a fresh Ruby process per file. This includes
# the VM, compressed input, decoder workspace, and returned Image.
require "open3"
require "rbconfig"

lib = File.expand_path("../lib", __dir__)
paths = ARGV
if paths.empty?
  paths = %w[a.jpg a-progressive.jpg].map { |name| File.expand_path("../examples/#{name}", __dir__) }
end
worker = <<~'CODE'
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  image = PureJPEG.read(ARGV.fetch(0))
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts format("%dx%d  %.3f s", image.width, image.height, seconds)
CODE

case RbConfig::CONFIG.fetch("host_os")
when /darwin/
  time_args = ["-l"]
  peak_pattern = /(\d+)\s+maximum resident set size/
  units_per_mib = 1024 * 1024
when /linux/
  time_args = ["-f", "peak_kib=%M"]
  peak_pattern = /peak_kib=(\d+)/
  units_per_mib = 1024
else
  abort "This benchmark uses /usr/bin/time on macOS or GNU time on Linux."
end

paths.each do |path|
  output, stats, status = Open3.capture3({ "LC_ALL" => "C" }, "/usr/bin/time", *time_args,
                                         RbConfig.ruby, "-I", lib, "-rpure_jpeg", "-e", worker, "--", path)
  abort stats unless status.success?
  peak = stats[peak_pattern, 1]
  abort "Missing peak RSS in #{stats}" unless peak
  puts format("%s  %s  %.1f MiB peak RSS", path, output.strip, peak.to_i.fdiv(units_per_mib))
end
