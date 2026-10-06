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

good = Zlib::Deflate.deflate("hello, hello, hello", 6)
inflate("\x78\x9d".b, 15, "wrong header check")
inflate("\x79\x18".b, 15, "compression method 9")
inflate("\x88\x1c".b, 15, "window 32K past the limit")
inflate(good[0, 2] + Zlib::Deflate.new(6, -9).deflate("smaller window", Zlib::FINISH), 8, "window larger than asked")
inflate(good.dup.tap { |s| s.setbyte(-1, s.getbyte(-1) ^ 1) }, 15, "adler32 off by one")
inflate(good[0..-2], 15, "adler32 cut short")
inflate(good.dup.tap { |s| s.setbyte(5, s.getbyte(5) ^ 0x40) }, 15, "a flipped bit inside")
inflate("".b, 15, "nothing")
inflate(good, 15, "good zlib stream")
inflate(good, -15, "zlib stream read as raw")
inflate(good, 31, "zlib stream read as gzip")
inflate(good, 47, "zlib stream with auto detection")

