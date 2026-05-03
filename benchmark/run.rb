#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive benchmark for PureJPEG encode and decode paths.
#
# Usage:
#   ruby benchmark/run.rb                    # Standard benchmark (default)
#   ruby benchmark/run.rb --quick            # Shorter benchmark
#   ruby benchmark/run.rb --full             # Longer benchmark with YJIT stats
#   ruby benchmark/run.rb --profile          # CPU profile with Vernier
#   ruby benchmark/run.rb --profile-alloc    # Allocation profile with Vernier
#
# All modes automatically use YJIT if available.

require "bundler/inline"

profile_mode = ARGV.include?("--profile") || ARGV.include?("--profile-alloc")

gemfile(true, quiet: true) do
  source "https://rubygems.org"
  gem "benchmark"
  gem "benchmark-ips"
  gem "chunky_png", "~> 1.4"
  gem "vernier" if profile_mode
end

require_relative "../lib/pure_jpeg"

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

EXAMPLES_DIR = File.expand_path("../examples", __dir__)
PNG_PATH     = File.join(EXAMPLES_DIR, "a.png")
JPEG_PATH    = File.join(EXAMPLES_DIR, "a.jpg")
PROG_PATH    = File.join(EXAMPLES_DIR, "a-progressive.jpg")

abort "Missing #{PNG_PATH}" unless File.exist?(PNG_PATH)
abort "Missing #{JPEG_PATH}" unless File.exist?(JPEG_PATH)

mode = case
       when ARGV.include?("--full")          then :full
       when ARGV.include?("--quick")         then :quick
       when ARGV.include?("--profile")       then :profile_cpu
       when ARGV.include?("--profile-alloc") then :profile_alloc
       else :standard
       end

BENCHMARK_CONFIG = {
  quick: { warmup: 0, time: 0, samples: 1, warmup_iterations: 0 },
  standard: { warmup: 3, time: 5, samples: 5, warmup_iterations: 2 },
  full: { warmup: 3, time: 5, samples: 7, warmup_iterations: 5 }
}.fetch(mode, { warmup: 3, time: 5, samples: 5, warmup_iterations: 2 })

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
if mode == :quick
  puts "Mode:               quick"
else
  puts "Mode:               #{mode} (warmup: #{BENCHMARK_CONFIG[:warmup]}s, time: #{BENCHMARK_CONFIG[:time]}s)"
end
puts

# --- Warmup (important for YJIT) ---
if BENCHMARK_CONFIG[:warmup_iterations].positive?
  puts "Warming up..."
  BENCHMARK_CONFIG[:warmup_iterations].times do
    PureJPEG.encode(source, quality: 85).to_bytes
    PureJPEG.read(jpeg_bytes)
    PureJPEG.read(prog_bytes) if prog_bytes
  end
  puts
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
  after - before
rescue ArgumentError, NotImplementedError
  nil
ensure
  GC.enable
end

def format_allocations(count)
  count.nil? ? "N/A" : "#{count} objects"
end

def wall_clock_samples(samples)
  samples.times.map do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
end

def print_times(label, times)
  formatted = times.map { |t| "%.3fs" % t }.join(", ")
  puts "#{label}: #{formatted} (best: #{'%.3fs' % times.min})"
end

if mode == :quick
  puts "=== Quick Wall-clock ==="
  print_times("Encode q85", wall_clock_samples(1) { PureJPEG.encode(source, quality: 85).to_bytes })
  print_times("Decode baseline", wall_clock_samples(1) { PureJPEG.read(jpeg_bytes) })
  print_times("Decode progressive", wall_clock_samples(1) { PureJPEG.read(prog_bytes) }) if prog_bytes
  puts

  puts "=== Quick Object Allocations ==="
  puts "Encode q85:        #{format_allocations(measure_allocations { PureJPEG.encode(source, quality: 85).to_bytes })}"
  puts "Decode baseline:   #{format_allocations(measure_allocations { PureJPEG.read(jpeg_bytes) })}"
  puts "Decode progressive: #{format_allocations(measure_allocations { PureJPEG.read(prog_bytes) })}" if prog_bytes
  puts
  puts "Done."
  exit
end

puts "=== Object Allocations ==="
encode_allocs = measure_allocations { PureJPEG.encode(source, quality: 85).to_bytes }
puts "Encode (1024x1024):             #{format_allocations(encode_allocs)}"

encode_opt_allocs = measure_allocations { PureJPEG.encode(source, quality: 95, optimize_huffman: true).to_bytes }
puts "Encode optimized (1024x1024):   #{format_allocations(encode_opt_allocs)}"

decode_allocs = measure_allocations { PureJPEG.read(jpeg_bytes) }
puts "Decode baseline (1024x1024):    #{format_allocations(decode_allocs)}"

if prog_bytes
  prog_allocs = measure_allocations { PureJPEG.read(prog_bytes) }
  puts "Decode progressive (1024x1024): #{format_allocations(prog_allocs)}"
end
puts

# ==========================================================================
# Throughput (iterations/second)
# ==========================================================================
puts "=== Throughput (iterations/second) ==="
Benchmark.ips do |x|
  x.config(time: BENCHMARK_CONFIG[:time], warmup: BENCHMARK_CONFIG[:warmup])

  x.report("encode 1024x1024 q85") do
    PureJPEG.encode(source, quality: 85).to_bytes
  end

  x.report("encode 1024x1024 q95 optimized") do
    PureJPEG.encode(source, quality: 95, optimize_huffman: true).to_bytes
  end

  x.report("encode 1024x1024 grayscale") do
    PureJPEG.encode(source, quality: 85, grayscale: true).to_bytes
  end

  x.report("decode baseline 1024x1024") do
    PureJPEG.read(jpeg_bytes)
  end

  if prog_bytes
    x.report("decode progressive 1024x1024") do
      PureJPEG.read(prog_bytes)
    end
  end
end
puts

# ==========================================================================
# Wall-clock times
# ==========================================================================
puts "=== Wall-clock times (best of #{BENCHMARK_CONFIG[:samples]}) ==="

encode_times = wall_clock_samples(BENCHMARK_CONFIG[:samples]) do
  PureJPEG.encode(source, quality: 85).to_bytes
end
print_times("Encode q85", encode_times)

encode_opt_times = wall_clock_samples(BENCHMARK_CONFIG[:samples]) do
  PureJPEG.encode(source, quality: 95, optimize_huffman: true).to_bytes
end
print_times("Encode q95 optimized", encode_opt_times)

decode_times = wall_clock_samples(BENCHMARK_CONFIG[:samples]) do
  PureJPEG.read(jpeg_bytes)
end
print_times("Decode baseline", decode_times)

if prog_bytes
  prog_times = wall_clock_samples(BENCHMARK_CONFIG[:samples]) do
    PureJPEG.read(prog_bytes)
  end
  print_times("Decode progressive", prog_times)
end

puts

# ==========================================================================
# Sustained mixed workload
# ==========================================================================
puts "=== Sustained mixed workload ==="
mixed_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
BENCHMARK_CONFIG[:samples].times do
  PureJPEG.encode(source, quality: 85).to_bytes
  PureJPEG.encode(source, quality: 95, optimize_huffman: true).to_bytes
  PureJPEG.read(jpeg_bytes)
  PureJPEG.read(prog_bytes) if prog_bytes
end
mixed_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - mixed_start
puts "#{BENCHMARK_CONFIG[:samples]} encode/decode batches completed in #{'%.3fs' % mixed_elapsed}"
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
