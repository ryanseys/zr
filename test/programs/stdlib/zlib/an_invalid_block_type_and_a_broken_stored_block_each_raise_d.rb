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

inflate(block { |b| b.put(1, 1); b.put(3, 2) }, -15, "block type 3")
inflate(block { |b| b.put(1, 1); b.put(0, 2); b.align; b.put(5, 16); b.put(0, 16) }, -15, "stored lengths")
inflate(block { |b| b.put(1, 1); b.put(0, 2); b.align; b.put(3, 16); b.put(0xfffc, 16); b.put(0x41, 8) }, -15, "stored block cut short")
inflate(block { |b| b.put(1, 1); b.put(2, 2); b.put(30, 5); b.put(0, 5); b.put(0, 4) }, -15, "too many symbols")
inflate(block { |b| b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4); 4.times { b.put(1, 3) } }, -15, "code lengths over-subscribed")
inflate(block { |b|
  b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
  [1, 2, 2, 0].each { |len| b.put(len, 3) } # 16: "0", 17: "10", 18: "11"
  b.code(0b0, 1) # repeat with nothing before it
}, -15, "repeat with no previous length")
inflate(block { |b|
  b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
  [0, 2, 2, 1].each { |len| b.put(len, 3) } # 0: "0", 17: "10", 18: "11"
  b.code(0b11, 2); b.put(127, 7) # 138 zeros
  b.code(0b11, 2); b.put(109, 7) # 120 zeros: 258 in all
}, -15, "no end-of-block code")
inflate(block { |b|
  b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
  [0, 2, 2, 1].each { |len| b.put(len, 3) }
  b.code(0b11, 2); b.put(127, 7)
  b.code(0b11, 2); b.put(127, 7) # 276 > 258
}, -15, "repeat runs past the end")
inflate(block { |b|
  b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(14, 4)
  # order 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1: lengths for 0 and 18 are 2 bits, for 1 one bit
  [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1].each { |len| b.put(len, 3) }
  3.times { b.code(0b0, 1) }          # symbols 0..2 with length 1: over-subscribed
  b.code(0b11, 2); b.put(127, 7)      # 138 zeros
  b.code(0b11, 2); b.put(104, 7)      # 115 zeros: 256 so far
  b.code(0b0, 1)                      # 256 has length 1
  b.code(0b10, 2)                     # the one distance length: 0
}, -15, "literal lengths over-subscribed")
inflate(block { |b|
  b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(2, 5); b.put(14, 4)
  [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1].each { |len| b.put(len, 3) }
  b.code(0b0, 1)                      # symbol 0 length 1
  b.code(0b11, 2); b.put(127, 7)      # 138 zeros
  b.code(0b11, 2); b.put(106, 7)      # 117 zeros: 256 so far
  b.code(0b0, 1)                      # 256 length 1: complete
  3.times { b.code(0b0, 1) }          # three distances of length 1: over-subscribed
}, -15, "distance lengths over-subscribed")
inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 257); b.code(4, 5); b.put(0, 1); fixed_lit(b, 256) }, -15, "distance before the start")
inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 257); b.code(30, 5) }, -15, "distance code 30")
inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 286) }, -15, "literal code 286")
inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 0x62); fixed_lit(b, 256) }, -15, "a good fixed block")
inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61) }, -15, "cut before the end-of-block")

