#!/usr/bin/env ruby
# frozen_string_literal: true
#
# YJIT Disassembly Script
# Run with: /Users/ufuk/.rubies/ruby-master/bin/ruby --yjit benchmark/disasm.rb
#
# Warms up hot methods, then dumps YJIT disassembly (bytecode + ARM64 native
# code) for analysis.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pure_jpeg"

# Create a small test image for warmup (64x64 is enough to exercise all paths)
width = 64
height = 64
pixels = Array.new(width * height) { |i|
  r = (i * 3) & 0xFF
  g = (i * 7) & 0xFF
  b = (i * 11) & 0xFF
  (r << 16) | (g << 8) | b
}
img = PureJPEG::Image.new(width, height, pixels)

# Warm up encode path (multiple iterations to trigger YJIT compilation)
puts "Warming up encode path..."
encoded_bytes = PureJPEG.encode(img, quality: 85).to_bytes
20.times do
  PureJPEG.encode(img, quality: 85).to_bytes
  # Warm up decode path too
  PureJPEG.read(encoded_bytes)
end
puts "Warmup done."

# Now disassemble hot methods
output_dir = File.expand_path("../benchmark/disasm_output", __dir__)
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

methods_to_disasm = []

# DCT methods (class methods)
methods_to_disasm << ["DCT.forward!", PureJPEG::DCT.method(:forward!)]
methods_to_disasm << ["DCT.inverse!", PureJPEG::DCT.method(:inverse!)]

# Quantization methods (class methods)
methods_to_disasm << ["Quantization.quantize!", PureJPEG::Quantization.method(:quantize!)]
methods_to_disasm << ["Quantization.dequantize!", PureJPEG::Quantization.method(:dequantize!)]

# Encoder instance methods - need an encoder instance
encoder = PureJPEG::Encoder.new(img, quality: 85)
methods_to_disasm << ["Encoder#extract_ycbcr", encoder.method(:extract_ycbcr)]
methods_to_disasm << ["Encoder#extract_block_into", encoder.method(:extract_block_into)]
methods_to_disasm << ["Encoder#downsample", encoder.method(:downsample)]
methods_to_disasm << ["Encoder#transform_block", encoder.method(:transform_block)]

# Decoder instance methods - need a decoder instance
decoder = PureJPEG::Decoder.new(encoded_bytes)
methods_to_disasm << ["Decoder#write_block", decoder.method(:write_block)]
methods_to_disasm << ["Decoder#assemble_color", decoder.method(:assemble_color)]
methods_to_disasm << ["Decoder#decode_block", decoder.method(:decode_block)]

# BitWriter
bw = PureJPEG::BitWriter.new
methods_to_disasm << ["BitWriter#write_bits", bw.method(:write_bits)]

# Zigzag
methods_to_disasm << ["Zigzag.reorder!", PureJPEG::Zigzag.method(:reorder!)]
methods_to_disasm << ["Zigzag.unreorder!", PureJPEG::Zigzag.method(:unreorder!)]

# Huffman DecodeTable#decode
# We need to find an instance - create one from standard tables
dt = PureJPEG::Huffman::DecodeTable.new(
  PureJPEG::Huffman::DC_LUMINANCE_BITS,
  PureJPEG::Huffman::DC_LUMINANCE_VALUES
)
methods_to_disasm << ["Huffman::DecodeTable#decode", dt.method(:decode)]

# BitReader
br = PureJPEG::BitReader.new("\xFF\xD8\xFF\x00\x01\x02".b)
methods_to_disasm << ["BitReader#read_bit", br.method(:read_bit)]
methods_to_disasm << ["BitReader#read_bits", br.method(:read_bits)]
methods_to_disasm << ["BitReader#receive_extend", br.method(:receive_extend)]

puts "\nDisassembling #{methods_to_disasm.length} methods...\n\n"

methods_to_disasm.each do |name, method_obj|
  filename = name.gsub(/[#.:!]/, "_").gsub(/__+/, "_").downcase + ".txt"
  filepath = File.join(output_dir, filename)

  begin
    disasm = RubyVM::YJIT.disasm(method_obj)
    if disasm && !disasm.empty?
      File.write(filepath, "# YJIT Disassembly for: #{name}\n# Method: #{method_obj}\n\n#{disasm}")
      lines = disasm.lines.count
      puts "  #{name}: #{lines} lines -> #{filepath}"
    else
      puts "  #{name}: NOT COMPILED (no disassembly available)"
    end
  rescue => e
    puts "  #{name}: ERROR - #{e.message}"
  end
end

puts "\nDone! Output written to #{output_dir}/"

# Also dump YJIT stats summary
if RubyVM::YJIT.respond_to?(:runtime_stats)
  stats = RubyVM::YJIT.runtime_stats
  puts "\n--- YJIT Stats Summary ---"
  puts "  yjit_alloc_size: #{stats[:yjit_alloc_size]}" if stats[:yjit_alloc_size]
  puts "  compiled_iseq_count: #{stats[:compiled_iseq_count]}" if stats[:compiled_iseq_count]
  puts "  compiled_blockid_count: #{stats[:compiled_blockid_count]}" if stats[:compiled_blockid_count]
  puts "  inline_code_size: #{stats[:inline_code_size]}" if stats[:inline_code_size]
  puts "  outlined_code_size: #{stats[:outlined_code_size]}" if stats[:outlined_code_size]
  side_exits = stats.select { |k, _| k.to_s.start_with?("exit_") && _ > 0 }
  unless side_exits.empty?
    puts "\n  Top side exits:"
    side_exits.sort_by { |_, v| -v }.first(20).each do |k, v|
      puts "    #{k}: #{v}"
    end
  end
end
