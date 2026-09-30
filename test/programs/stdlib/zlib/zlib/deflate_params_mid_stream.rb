# deflateParams between appends: what the old parameters compressed is
# flushed, the new ones compress the rest, and the bytes are ruby's.
# (`<<` keeps the output buffer; ruby's params after `deflate` reads a
# buffer it gave away, so the row does not do that.)
require "zlib"

def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

text = Array.new(400) { |i| "line #{i % 17} of the text\n" }.join

changes = [
  [1, Zlib::DEFAULT_STRATEGY],
  [9, Zlib::DEFAULT_STRATEGY],
  [6, Zlib::HUFFMAN_ONLY],
  [6, Zlib::RLE],
  [0, Zlib::DEFAULT_STRATEGY],
  [5, Zlib::FIXED],
  [3, Zlib::FILTERED],
]
changes.each do |level, strategy|
  d = Zlib::Deflate.new(6)
  d << text[0, 1500]
  d.params(level, strategy)
  d << text[1500..]
  out = d.finish
  d.close
  puts "to #{level}/#{strategy}: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"
  raise "no round trip" unless Zlib::Inflate.inflate(out) == text
end

d = Zlib::Deflate.new(1)
d << "a few bytes"
d.params(9, Zlib::DEFAULT_STRATEGY)
d << " and a few more bytes, a few more bytes"
puts "short: #{hex(d.finish)}"
d.close

d = Zlib::Deflate.new(9)
d << text
d.params(1, Zlib::DEFAULT_STRATEGY)
d.params(9, Zlib::DEFAULT_STRATEGY)
d << text
out = d.finish
d.close
puts "two changes: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"

d = Zlib::Deflate.new(6)
d << "same"
d.params(6, Zlib::DEFAULT_STRATEGY)
d << " params again"
puts "same params again: #{hex(d.finish)}"
d.close

d = Zlib::Deflate.new(6)
d << "x" * 3000
d.params(0, Zlib::DEFAULT_STRATEGY)
d << "y" * 3000
d.params(6, Zlib::DEFAULT_STRATEGY)
d << "z" * 3000
out = d.finish
d.close
puts "through stored: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"
puts "reads back: #{Zlib::Inflate.inflate(out) == "x" * 3000 + "y" * 3000 + "z" * 3000}"

