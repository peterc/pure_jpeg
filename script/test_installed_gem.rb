# frozen_string_literal: true

# Test the built artifact outside the checkout, without development gems.
require "tmpdir"
require "open3"
require "rubygems"

root = File.expand_path("..", __dir__)
Dir.mktmpdir("pure-jpeg-gem") do |dir|
  gem_path = File.join(dir, "pure_jpeg.gem")
  home = File.join(dir, "gems")
  env = { "GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
  run = lambda do |*args, **options|
    out, err, status = Open3.capture3(env, Gem.ruby, *args, **options)
    abort "#{args.inspect}\n#{out}\n#{err}" unless status.success?
  end
  run.call("-S", "gem", "build", "pure_jpeg.gemspec", "--output", gem_path, chdir: root)
  run.call("-S", "gem", "install", "--local", "--no-document", gem_path, chdir: dir)
  run.call("-e", <<~'RUBY', chdir: dir)
    require "pure_jpeg"
    source = PureJPEG::Source::RawSource.new(17, 13) { |x, y| [x * 12, y * 16, 80] }
    bytes = PureJPEG.encode(source).to_bytes
    image = PureJPEG.read(bytes)
    raise "wrong dimensions" unless [image.width, image.height] == [17, 13]
    raise "missing documentation" unless File.exist?(File.join(Gem.loaded_specs.fetch("pure_jpeg").full_gem_path, "CREATIVE.md"))
  RUBY
end
puts "Installed gem smoke test passed"
