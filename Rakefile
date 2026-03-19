require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/test_*.rb"]
end

desc "Benchmark encoding and decoding (3 runs each)"
task :benchmark do
  require "chunky_png"
  require_relative "lib/pure_jpeg"

  runs = 3

  def bench(label, runs, &block)
    # Warmup
    block.call

    times = runs.times.map do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      block.call
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    end

    avg = times.sum / times.length
    puts "  #{label}: #{times.map { |t| '%.3fs' % t }.join(', ')} (avg #{'%.3fs' % avg})"
  end

  # Encode
  image = ChunkyPNG::Image.from_file(File.expand_path("examples/a.png", __dir__))
  source = PureJPEG::Source::ChunkyPNGSource.new(image)

  puts "Encode #{image.width}x#{image.height} (color, q85):"
  bench("Encode", runs) do
    PureJPEG.encode(source, quality: 85).write("/tmp/bench_output.jpg")
  end

  # Decode baseline
  baseline_path = File.expand_path("examples/a.jpg", __dir__)
  info = PureJPEG.info(baseline_path)
  puts "\nDecode baseline #{info.width}x#{info.height}:"
  bench("Decode", runs) do
    PureJPEG::Decoder.decode(baseline_path)
  end

  # Decode progressive
  progressive_path = File.expand_path("examples/a-progressive.jpg", __dir__)
  info = PureJPEG.info(progressive_path)
  puts "\nDecode progressive #{info.width}x#{info.height}:"
  bench("Decode", runs) do
    PureJPEG::Decoder.decode(progressive_path)
  end
end

desc "Profile encoding with StackProf (requires stackprof gem)"
task :profile do
  require "stackprof"
  require "chunky_png"
  require_relative "lib/pure_jpeg"

  image = ChunkyPNG::Image.from_file(File.expand_path("examples/a.png", __dir__))
  source = PureJPEG::Source::ChunkyPNGSource.new(image)

  dump_path = "/tmp/pure_jpeg_profile.dump"
  StackProf.run(mode: :cpu, out: dump_path, raw: true) do
    PureJPEG.encode(source, quality: 85).write("/tmp/profiled_output.jpg")
  end

  puts StackProf::Report.new(Marshal.load(File.binread(dump_path))).print_text
end

task default: :test
