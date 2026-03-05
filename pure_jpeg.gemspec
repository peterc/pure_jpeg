require_relative "lib/pure_jpeg/version"

Gem::Specification.new do |spec|
  spec.name    = "pure_jpeg"
  spec.version = PureJPEG::VERSION
  spec.authors = ["Peter"]
  spec.summary = "Pure Ruby JPEG encoder and decoder"
  spec.description = "A pure Ruby baseline JPEG encoder and decoder with no native dependencies."
  spec.license = "MIT"
  spec.homepage = "https://github.com/peterc/pure_jpeg"

  spec.metadata = {
    "source_code_uri" => "https://github.com/peterc/pure_jpeg",
    "changelog_uri"   => "https://github.com/peterc/pure_jpeg/blob/main/CHANGELOG.md",
  }

  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "chunky_png", "~> 1.4"
  spec.add_development_dependency "minitest", "~> 5.0"
end
