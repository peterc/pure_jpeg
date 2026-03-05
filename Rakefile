require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/test_*.rb"]
end

desc "Benchmark encoding (3 runs, uses examples/a.png)"
task :benchmark do
  require "chunky_png"
  require_relative "lib/pure_jpeg"

  image = ChunkyPNG::Image.from_file(File.expand_path("examples/a.png", __dir__))
  source = PureJPEG::Source::ChunkyPNGSource.new(image)

  # Warmup
  PureJPEG.encode(source, quality: 85).write("/tmp/bench_output.jpg")

  times = 3.times.map do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    PureJPEG.encode(source, quality: 85).write("/tmp/bench_output.jpg")
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end

  avg = times.sum / times.length
  puts "Image: #{image.width}x#{image.height}"
  puts "Output: #{File.size('/tmp/bench_output.jpg')} bytes"
  puts "Times: #{times.map { |t| '%.3fs' % t }.join(', ')}"
  puts "Average: #{'%.3fs' % avg}"
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
