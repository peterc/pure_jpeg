#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive benchmark for PureJPEG encode and decode paths.
#
# Usage:
#   ruby benchmark/run.rb                    # Quick benchmark (default)
#   ruby benchmark/run.rb --full             # Full benchmark with YJIT stats
#   ruby benchmark/run.rb --profile          # CPU profile with Vernier
#   ruby benchmark/run.rb --profile-alloc    # Allocation profile with Vernier
#
# All modes automatically use YJIT if available.

require "bundler/inline"

gemfile(true, quiet: true) do
  source "https://rubygems.org"
  gem "benchmark"
  gem "benchmark-ips"
  gem "chunky_png", "~> 1.4"
  gem "vernier"
end

require_relative "../lib/pure_jpeg"

EXAMPLES_DIR = File.expand_path("../examples", __dir__)
PNG_PATH     = File.join(EXAMPLES_DIR, "a.png")
JPEG_PATH    = File.join(EXAMPLES_DIR, "a.jpg")
PROG_PATH    = File.join(EXAMPLES_DIR, "a-progressive.jpg")

abort "Missing #{PNG_PATH}" unless File.exist?(PNG_PATH)
abort "Missing #{JPEG_PATH}" unless File.exist?(JPEG_PATH)

mode = case
       when ARGV.include?("--full")          then :full
       when ARGV.include?("--profile")       then :profile_cpu
       when ARGV.include?("--profile-alloc") then :profile_alloc
       else :quick
       end

# --- Setup ---
puts "=== PureJPEG Benchmark ==="
puts "Ruby:  #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "YJIT:  #{defined?(RubyVM::YJIT) ? "enabled" : "disabled"}"
puts

png_image   = ChunkyPNG::Image.from_file(PNG_PATH)
source      = PureJPEG::Source::ChunkyPNGSource.new(png_image)
jpeg_bytes  = File.binread(JPEG_PATH)
prog_bytes  = File.exist?(PROG_PATH) ? File.binread(PROG_PATH) : nil

puts "Encode source:      #{source.width}x#{source.height} PNG"
puts "Decode source:      #{jpeg_bytes.bytesize} bytes baseline JPEG"
puts "Progressive source: #{prog_bytes&.bytesize || 'N/A'} bytes"
puts

# --- Warmup (important for YJIT) ---
puts "Warming up..."
5.times do
  PureJPEG.encode(source, quality: 85).to_bytes
  PureJPEG.read(jpeg_bytes)
end
puts

# ==========================================================================
# Vernier CPU profiling
# ==========================================================================
if mode == :profile_cpu
  require "vernier"

  puts "=== Vernier CPU Profile: Encode ==="
  path = "/tmp/pure_jpeg_encode_cpu.json"
  Vernier.profile(out: path) do
    3.times { PureJPEG.encode(source, quality: 85).to_bytes }
  end
  puts "  saved to #{path}"

  puts "=== Vernier CPU Profile: Decode ==="
  path = "/tmp/pure_jpeg_decode_cpu.json"
  Vernier.profile(out: path) do
    3.times { PureJPEG.read(jpeg_bytes) }
  end
  puts "  saved to #{path}"

  puts
  puts "View with:  vernier view /tmp/pure_jpeg_encode_cpu.json"
  puts "            vernier view /tmp/pure_jpeg_decode_cpu.json"
  exit
end

# ==========================================================================
# Vernier allocation profiling (retained objects)
# ==========================================================================
if mode == :profile_alloc
  require "vernier"

  puts "=== Vernier Retained-Object Profile: Encode ==="
  path = "/tmp/pure_jpeg_encode_retained.json"
  Vernier.profile(out: path, mode: :retained) do
    PureJPEG.encode(source, quality: 85).to_bytes
  end
  puts "  saved to #{path}"

  puts
  puts "=== Vernier Retained-Object Profile: Decode ==="
  path = "/tmp/pure_jpeg_decode_retained.json"
  Vernier.profile(out: path, mode: :retained) do
    PureJPEG.read(jpeg_bytes)
  end
  puts "  saved to #{path}"

  puts
  puts "View with:  vernier view /tmp/pure_jpeg_encode_retained.json"
  puts "            vernier view /tmp/pure_jpeg_decode_retained.json"
  exit
end

# ==========================================================================
# Allocation counting (quick GC.stat approach)
# ==========================================================================
def measure_allocations
  GC.start
  GC.disable
  before = GC.stat(:total_allocated_objects)
  yield
  after = GC.stat(:total_allocated_objects)
  GC.enable
  after - before
end

puts "=== Object Allocations ==="
encode_allocs = measure_allocations { PureJPEG.encode(source, quality: 85).to_bytes }
puts "Encode (1024x1024):             #{encode_allocs} objects"

decode_allocs = measure_allocations { PureJPEG.read(jpeg_bytes) }
puts "Decode baseline (1024x1024):    #{decode_allocs} objects"

if prog_bytes
  prog_allocs = measure_allocations { PureJPEG.read(prog_bytes) }
  puts "Decode progressive (1024x1024): #{prog_allocs} objects"
end
puts

# ==========================================================================
# Throughput (iterations/second)
# ==========================================================================
puts "=== Throughput (iterations/second) ==="
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("encode 1024x1024 q85") do
    PureJPEG.encode(source, quality: 85).to_bytes
  end

  x.report("decode baseline 1024x1024") do
    PureJPEG.read(jpeg_bytes)
  end

  if prog_bytes
    x.report("decode progressive 1024x1024") do
      PureJPEG.read(prog_bytes)
    end
  end

  x.compare!
end
puts

# ==========================================================================
# Wall-clock times
# ==========================================================================
puts "=== Wall-clock times (best of 3) ==="
encode_times = 3.times.map do
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  PureJPEG.encode(source, quality: 85).to_bytes
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end
puts "Encode: #{encode_times.map { |t| '%.3fs' % t }.join(', ')} (best: #{'%.3fs' % encode_times.min})"

decode_times = 3.times.map do
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  PureJPEG.read(jpeg_bytes)
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end
puts "Decode: #{decode_times.map { |t| '%.3fs' % t }.join(', ')} (best: #{'%.3fs' % decode_times.min})"
puts

# ==========================================================================
# YJIT stats (--full mode only)
# ==========================================================================
if mode == :full && defined?(RubyVM::YJIT)
  puts "=== YJIT Statistics ==="
  stats = RubyVM::YJIT.runtime_stats
  stats.sort_by { |k, _| k.to_s }.each do |k, v|
    next if v.is_a?(Integer) && v == 0
    next if v.is_a?(Hash)
    puts "  #{k}: #{v}"
  end
  puts
end

puts "Done."
