# frozen_string_literal: true

require "pure_jpeg"

begin
  PureJPEG.read("not a JPEG")
  raise "Accepted invalid JPEG data"
rescue PureJPEG::DecodeError => error
  puts "invalid JPEG: #{error.message}"
end

begin
  PureJPEG.info("\xFF\xD8\xFF\xD9".b)
  raise "Accepted a missing frame header"
rescue PureJPEG::DecodeError => error
  puts "missing frame: #{error.message}"
end

source = PureJPEG::Source::RawSource.new(8, 8) { |_x, _y| [0, 0, 0] }
[0, 101].each do |quality|
  begin
    PureJPEG.encode(source, quality: quality).to_bytes
    raise "Accepted invalid quality"
  rescue ArgumentError => error
    puts "quality #{quality}: #{error.message}"
  end
end
