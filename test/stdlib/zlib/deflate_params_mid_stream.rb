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

__END__
to 1/0: 199 bytes, crc 2061360847
to 9/0: 123 bytes, crc 255903217
to 6/2: 2938 bytes, crc 2975596962
to 6/3: 2938 bytes, crc 2975596962
to 0/0: 6358 bytes, crc 3179955064
to 5/4: 157 bytes, crc 2621264724
to 3/1: 155 bytes, crc 2081641720
short: 78014a54484b2d5748aa2c492d064c21312f452111cccfcd2f4a8508ea60880000b72e1184
two changes: 174 bytes, crc 3765246196
same params again: 789c2b4ecc4d5528482c4acc2d56484c4fcccc030039c6066b
through stored: 3050 bytes, crc 3422892248
reads back: true
