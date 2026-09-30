# Every message inflate gives for a broken stream, from hand-built
# streams: the block types, the code length sets, the distances, the
# wrappers' headers and trailers.
require "zlib"

# Bits packed least significant first, as deflate packs them; a Huffman
# code goes in most significant bit first.
class Bits
  def initialize = @bits = []
  def put(value, n) = n.times { |i| @bits << ((value >> i) & 1) }
  def code(value, n) = n.times { |i| @bits << ((value >> (n - 1 - i)) & 1) }
  def align = @bits.concat([0] * ((8 - @bits.size % 8) % 8))
  def bytes = @bits.each_slice(8).map { |s| s.each_with_index.sum { |b, i| b << i } }.pack("C*")
end

def inflate(bytes, wbits, label)
  i = Zlib::Inflate.new(wbits)
  out = i.inflate(bytes)
  out << i.finish if !i.finished? && i.avail_in.zero?
  puts "#{label}: ok #{out.inspect}"
rescue Zlib::Error => e
  puts "#{label}: #{e.class}: #{e.message}"
ensure
  i&.close
end

def block(&build) = Bits.new.tap(&build).bytes

# A fixed-Huffman literal, length or distance symbol.
def fixed_lit(b, sym)
  if sym <= 143 then b.code(0x30 + sym, 8)
  elsif sym <= 255 then b.code(0x190 + sym - 144, 9)
  elsif sym <= 279 then b.code(sym - 256, 7)
  else b.code(0xC0 + sym - 280, 8)
  end
end

gz = Zlib.gzip("gzip payload, gzip payload")
inflate(gz, 31, "good gzip")
inflate(gz, 47, "gzip with auto detection")
inflate(gz, 15, "gzip read as zlib")
inflate(gz.dup.tap { |s| s.setbyte(2, 7) }, 31, "gzip method 7")
inflate(gz.dup.tap { |s| s.setbyte(3, 0xe0) }, 31, "gzip reserved flags")
inflate(gz.dup.tap { |s| s.setbyte(-1, s.getbyte(-1) ^ 1) }, 31, "gzip length off")
inflate(gz.dup.tap { |s| s.setbyte(-5, s.getbyte(-5) ^ 1) }, 31, "gzip crc off")
hcrc = "\x1f\x8b\x08\x02\x00\x00\x00\x00\x00\x03\xff\xff".b + gz[10..]
inflate(hcrc, 31, "gzip header crc wrong")
named = "\x1f\x8b\x08\x08\x00\x00\x00\x00\x00\x03name\x00".b + gz[10..]
inflate(named, 31, "gzip with a name")
extra = "\x1f\x8b\x08\x04\x00\x00\x00\x00\x00\x03\x03\x00abc".b + gz[10..]
inflate(extra, 31, "gzip with an extra field")
inflate(gz + gz, 31, "two gzip members")

