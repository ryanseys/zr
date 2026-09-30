# The bytes each flush mode writes at each step of a stream, and that
# the way input is cut into calls does not change them.
require "zlib"

def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

parts = ["the first part, ", "a second part that repeats the first part, ", "and the last part."]
modes = {
  "NO_FLUSH" => Zlib::NO_FLUSH,
  "SYNC_FLUSH" => Zlib::SYNC_FLUSH,
  "FULL_FLUSH" => Zlib::FULL_FLUSH,
}
modes.each do |name, mode|
  d = Zlib::Deflate.new(6)
  parts.each_with_index do |part, n|
    puts "#{name} step #{n}: #{hex(d.deflate(part, mode))}"
  end
  puts "#{name} finish: #{hex(d.finish)}"
  d.close
end

d = Zlib::Deflate.new(9)
puts "flush(SYNC) on nothing: #{hex(d.flush(Zlib::SYNC_FLUSH))}"
d << "streamed with << "
puts "flush(SYNC): #{hex(d.flush(Zlib::SYNC_FLUSH))}"
puts "flush(FULL) on nothing: #{hex(d.flush(Zlib::FULL_FLUSH))}"
d << "and more"
puts "flush(FINISH): #{hex(d.flush(Zlib::FINISH))}"
d.close

text = ("chunking " * 3000) + ("x" * 70000) + ("chunking " * 100)
whole = Zlib::Deflate.deflate(text, 6)
[1, 7, 100, 4096, 65535, 65536].each do |size|
  d = Zlib::Deflate.new(6)
  out = +""
  text.bytes.each_slice(size) { |slice| out << d.deflate(slice.pack("C*")) }
  out << d.finish
  d.close
  puts "chunks of #{size}: #{out == whole ? "the same bytes" : "different bytes"}"
end
puts "whole: #{whole.bytesize} bytes, crc #{Zlib.crc32(whole)}"

