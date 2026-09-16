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

__END__
block type 3: Zlib::DataError: invalid block type
stored lengths: Zlib::DataError: invalid stored block lengths
stored block cut short: Zlib::BufError: buffer error
too many symbols: Zlib::DataError: too many length or distance symbols
code lengths over-subscribed: Zlib::DataError: invalid code lengths set
repeat with no previous length: Zlib::DataError: invalid bit length repeat
no end-of-block code: Zlib::DataError: invalid code -- missing end-of-block
repeat runs past the end: Zlib::DataError: invalid bit length repeat
literal lengths over-subscribed: Zlib::DataError: invalid literal/lengths set
distance lengths over-subscribed: Zlib::DataError: invalid distances set
distance before the start: Zlib::DataError: invalid distance too far back
distance code 30: Zlib::DataError: invalid distance code
literal code 286: Zlib::DataError: invalid literal/length code
a good fixed block: ok "ab"
cut before the end-of-block: Zlib::BufError: buffer error
wrong header check: Zlib::DataError: incorrect header check
compression method 9: Zlib::DataError: unknown compression method
window 32K past the limit: Zlib::DataError: invalid window size
window larger than asked: Zlib::DataError: invalid window size
adler32 off by one: Zlib::DataError: incorrect data check
adler32 cut short: Zlib::BufError: buffer error
a flipped bit inside: Zlib::DataError: incorrect data check
nothing: Zlib::BufError: buffer error
good zlib stream: ok "hello, hello, hello"
zlib stream read as raw: Zlib::DataError: invalid stored block lengths
zlib stream read as gzip: Zlib::DataError: incorrect header check
zlib stream with auto detection: ok "hello, hello, hello"
good gzip: ok "gzip payload, gzip payload"
gzip with auto detection: ok "gzip payload, gzip payload"
gzip read as zlib: Zlib::DataError: incorrect header check
gzip method 7: Zlib::DataError: unknown compression method
gzip reserved flags: Zlib::DataError: unknown header flags set
gzip length off: Zlib::DataError: incorrect length check
gzip crc off: Zlib::DataError: incorrect data check
gzip header crc wrong: Zlib::DataError: header crc mismatch
gzip with a name: ok "gzip payload, gzip payload"
gzip with an extra field: ok "gzip payload, gzip payload"
two gzip members: ok "gzip payload, gzip payload"
