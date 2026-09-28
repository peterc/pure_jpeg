# frozen_string_literal: true

# Discovery happens in CRuby; compiled programs contain only explicit calls.
abort "Use Ruby 3.0 or newer (e.g. mise exec ruby -- ruby script/test_spinel.rb)" if RUBY_VERSION.to_i < 3
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "timeout"

ROOT = File.expand_path("..", __dir__)
COMPILER = ENV.fetch("SPINEL", "spinel")
# Load assertions and helpers without Minitest autorun or coverage instrumentation.
require_relative "../test/support/spinel_test"
require_relative "../test/shared_helper"

files = ARGV.empty? ? ["test/test_raw_source.rb"] : ARGV
files = files.map { |file| File.expand_path(file, ROOT) }
# Mark the normal helper loaded for host-side discovery only. Generated tests
# explicitly load the adapter/shared helper instead.
$LOADED_FEATURES << File.join(ROOT, "test", "test_helper.rb")
files.each { |file| require file }
cases = ObjectSpace.each_object(Class).select { |klass| klass < Minitest::Test }.flat_map do |klass|
  klass.instance_methods.grep(/^test_/).filter_map do |method|
    source = klass.instance_method(method).source_location&.first
    [klass.name, method.to_s, source] if files.include?(source)
  end
end.sort
abort "No test methods found" if cases.empty?

build = File.join(ROOT, "tmp", "spinel-tests")
FileUtils.mkdir_p(build)

# A timeout must terminate the child too, not just stop waiting for it.
def capture(*command)
  output = +""
  status = nil
  Open3.popen2e(*command, pgroup: true) do |stdin, stdout, thread|
    stdin.close
    begin
      Timeout.timeout(120) do
        output = stdout.read
        status = thread.value
      end
    rescue Timeout::Error
      Process.kill("KILL", -thread.pid) rescue Errno::ESRCH
      thread.value
      return [false, "Timed out after 120 seconds"]
    end
  end
  [status.success?, output]
rescue Errno::ENOENT => error
  [false, error.message]
end

failures = 0
cases.each do |klass, method, source|
  name = "#{klass}##{method}"
  stem = name.gsub(/[^a-zA-Z0-9_]/, "_")
  program = File.join(build, "#{stem}.rb")
  binary = File.join(build, stem)
  test_source = File.read(source)
  helper_require = /^require_relative ["']test_helper["']$/
  abort "Expected one test_helper require in #{source}" unless test_source.scan(helper_require).length == 1
  adapter = Pathname.new(File.join(ROOT, "test/support/spinel_test.rb")).relative_path_from(Pathname.new(build))
  shared = Pathname.new(File.join(ROOT, "test/shared_helper.rb")).relative_path_from(Pathname.new(build))
  body = test_source.sub(helper_require, "require_relative #{adapter.to_s.dump}\nrequire_relative #{shared.to_s.dump}")
  File.write(program, <<~CODE)
    #{body}
    instance = #{klass}.new
    begin
      instance.setup
      instance.#{method}
    ensure
      instance.teardown
    end
    puts "PASS #{name}"
  CODE

  ruby_ok, ruby_output = capture(RbConfig.ruby, program)
  compile_ok, compile_output = capture(COMPILER, program, "--require-gate", "-o", binary)
  spinel_ok, spinel_output = compile_ok ? capture(binary) : [false, "Not run: compilation failed"]
  passed = ruby_ok && compile_ok && spinel_ok && ruby_output == spinel_output
  failures += 1 unless passed
  puts "#{passed ? 'PASS' : 'FAIL'} #{name}"
  log = "Ruby (#{ruby_ok}):\n#{ruby_output}\nCompile (#{compile_ok}):\n#{compile_output}\nSpinel (#{spinel_ok}):\n#{spinel_output}"
  File.write(File.join(build, "#{stem}.log"), log)
  puts log unless passed
end
puts "#{cases.length} tests, #{failures} failures; artifacts: #{build}"
exit(failures.zero? ? 0 : 1)
