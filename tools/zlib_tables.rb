# The tables zlib 1.3.1 computes once or ships in its headers, written
# as the kernel's read-only byte tables. Each is made from first
# principles here, the way zlib's own generators make them, so the file
# stays reproducible after the C is gone.
#
#   ruby tools/zlib_tables.rb > rt/kernel/zlib_tables.rb
#   ruby tools/zlib_tables.rb --check   # diffs against vendor/c/zlib while it exists
POLY = 0xedb88320

# crc32.c's make_crc_table: the CRC of every byte value.
def crc_table
  (0...256).map do |i|
    p = i
    8.times { p = p.odd? ? (p >> 1) ^ POLY : p >> 1 }
    p
  end
end

# crc32.c's multmodp: a(x) times b(x) modulo p(x), reflected.
def multmodp(a, b)
  m = 1 << 31
  p = 0
  loop do
    if (a & m) != 0
      p ^= b
      break if (a & (m - 1)).zero?
    end
    m >>= 1
    b = b.odd? ? (b >> 1) ^ POLY : b >> 1
  end
  p
end

# crc32.c's x^2^n mod p(x) table, 32 entries from x^1.
def x2n_table
  table = [1 << 30]
  31.times { table << multmodp(table.last, table.last) }
  table
end

# inftrees.c's base and extra-bit tables for the length and distance
# codes, and inflate.c's order of the code length code lengths.
LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 0, 0].freeze
LEXT = [16, 16, 16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 18, 18, 18, 18, 19, 19, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21, 16, 203, 77].freeze
DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 0, 0].freeze
DEXT = [16, 16, 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 25, 25, 26, 26, 27, 27, 28, 28, 29, 29, 64, 64].freeze
ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15].freeze

# A decoding table entry as the kernel packs it: op, bits, val.
def code(op, bits, val) = (op & 255) | ((bits & 255) << 8) | ((val & 65535) << 16)

# inftrees.c's inflate_table over `lens`, a canonical Huffman code, for
# a root table of `root` bits: the entries used, or nil for a bad code.
def inflate_table(type, lens, root)
  count = Array.new(16, 0)
  lens.each { |len| count[len] += 1 }
  max = 15
  max -= 1 while max >= 1 && count[max].zero?
  root = max if root > max
  return [code(64, 1, 0), code(64, 1, 0)] if max.zero?

  min = 1
  min += 1 while min < max && count[min].zero?
  root = min if root < min
  left = 1
  (1..15).each do |len|
    left <<= 1
    left -= count[len]
    return nil if left.negative?
  end
  return nil if left.positive? && (type == :codes || max != 1)

  offs = Array.new(16, 0)
  (1...15).each { |len| offs[len + 1] = offs[len] + count[len] }
  work = Array.new(lens.size, 0)
  lens.each_with_index { |len, sym| next if len.zero?; work[offs[len]] = sym; offs[len] += 1 }
  base, extra, match = { codes: [work, work, 20], lens: [LBASE, LEXT, 257], dists: [DBASE, DEXT, 0] }.fetch(type)
  table = []
  huff = 0
  sym = 0
  len = min
  at = 0
  curr = root
  drop = 0
  low = -1
  used = 1 << root
  mask = used - 1
  loop do
    w = work[sym]
    here = if w + 1 < match then code(0, len - drop, w)
           elsif w >= match then code(extra[w - match], len - drop, base[w - match])
           else code(96, len - drop, 0)
           end
    incr = 1 << (len - drop)
    fill = 1 << curr
    min = fill
    loop do
      fill -= incr
      table[at + (huff >> drop) + fill] = here
      break if fill.zero?
    end
    incr = 1 << (len - 1)
    incr >>= 1 while (huff & incr) != 0
    huff = incr.zero? ? 0 : (huff & (incr - 1)) + incr
    sym += 1
    count[len] -= 1
    if count[len].zero?
      break if len == max

      len = lens[work[sym]]
    end
    next unless len > root && (huff & mask) != low

    drop = root if drop.zero?
    at += min
    curr = len - drop
    left = 1 << curr
    while curr + drop < max
      left -= count[curr + drop]
      break if left <= 0

      curr += 1
      left <<= 1
    end
    used += 1 << curr
    low = huff & mask
    table[low] = code(curr, root, at)
  end
  table[at + huff] = code(64, len - drop, 0) unless huff.zero?
  table.first(used)
end

# inflate.c's fixed tables, as inffixed.h ships them: makefixed writes
# the two invalid length codes as a plain 64.
def lenfix
  lens = ([8] * 144) + ([9] * 112) + ([7] * 24) + ([8] * 8)
  inflate_table(:lens, lens, 9).each_with_index.map { |c, low| (low & 127) == 99 ? code(64, (c >> 8) & 255, c >> 16) : c }
end

def distfix = inflate_table(:dists, [5] * 32, 5)

# A def answering `words` as little-endian 32-bit cells, in rows of 32
# bytes joined by line continuations.
def emit_u32(name, words, comment)
  rows = words.pack("V*").bytes.each_slice(32).map { |row| row.map { |b| format("\\x%02X", b) }.join }
  puts "# #{comment}"
  puts "sig [] => Ptr"
  puts "machine def #{name}"
  puts "  Machine.bytes("
  puts "  \"#{rows.join("\\\n")}\")"
  puts "end"
  puts
end

# The C header's array named `name`, as integers.
def c_array(path, name)
  text = File.read(path)
  body = text[/#{name}\[\] = \{(.*?)\};/m, 1] or abort("no #{name} in #{path}")
  body.scan(/0x[0-9a-f]+/i).map { |h| h.hex }
end

# inffixed.h's `{op,bits,val}` rows named `name`, packed.
def c_codes(path, name)
  text = File.read(path)
  body = text[/#{name}\[\d+\] = \{(.*?)\};/m, 1] or abort("no #{name} in #{path}")
  body.scan(/\{(\d+),(\d+),(\d+)\}/).map { |op, bits, val| code(op.to_i, bits.to_i, val.to_i) }
end

if ARGV.include?("--check")
  src = File.expand_path("../vendor/c/zlib", __dir__)
  raise "crc_table differs" unless c_array(File.join(src, "crc32.h"), "crc_table") == crc_table
  raise "x2n_table differs" unless c_array(File.join(src, "crc32.h"), "x2n_table") == x2n_table
  raise "lenfix differs" unless c_codes(File.join(src, "inffixed.h"), "lenfix") == lenfix
  raise "distfix differs" unless c_codes(File.join(src, "inffixed.h"), "distfix") == distfix
  puts "zlib tables match vendor/c/zlib"
  exit
end

puts "# Generated by tools/zlib_tables.rb. Do not edit."
puts "#"
puts "# zlib's tables, made as crc32.c and trees.c make them; the license is"
puts "# in rt/kernel/zlib.rb."
puts
emit_u32("zr_crc_table", crc_table, "The CRC of every byte value, 256 words: crc32.c's crc_table, which get_crc_table answers too.")
emit_u32("zr_crc_x2n_table", x2n_table, "x^(2^n) modulo p(x) for n in 0...32: crc32.c's x2n_table, which crc32_combine reads.")
emit_u32("zr_inflate_lenfix", lenfix, "The fixed literal and length decoding table, 512 packed codes: inffixed.h's lenfix.")
emit_u32("zr_inflate_distfix", distfix, "The fixed distance decoding table, 32 packed codes: inffixed.h's distfix.")
emit_u32("zr_inflate_lbase", LBASE, "The base lengths of the length codes 257..285, then two zeros: inftrees.c's lbase.")
emit_u32("zr_inflate_lext", LEXT, "The extra bits of the length codes, with the two invalid codes marked: inftrees.c's lext.")
emit_u32("zr_inflate_dbase", DBASE, "The base distances of the distance codes 0..29, then two zeros: inftrees.c's dbase.")
emit_u32("zr_inflate_dext", DEXT, "The extra bits of the distance codes, with the two invalid codes marked: inftrees.c's dext.")
emit_u32("zr_inflate_order", ORDER, "The order the code length code lengths arrive in: inflate.c's order.")
