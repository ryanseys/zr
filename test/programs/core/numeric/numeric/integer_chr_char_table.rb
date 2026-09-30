# `Integer#chr` answers a 1-byte string for each byte value. The static
# table of 1-byte strings serves it, so a call allocates nothing.
#
# Byte 0 is a 1-byte string, not the empty string.

p 0.chr.length
p 0.chr.bytesize
p 0.chr.ord
p 0.chr.bytes
p 65.chr
p 65.chr.length
p 65.chr.bytes
p 65.chr.ord
p 255.chr.bytes
p 255.chr.bytesize
p 255.chr.ord
p 127.chr.ord

# building with chr
p 65.chr + 66.chr
p (65.chr + 66.chr).length
p [72, 105].map { |c| c.chr }.join
s = String.new("x")
s << 65.chr
p s
p s.length
p 65.chr == "A"
p "abc".include?(97.chr)
p "abc".index(98.chr)
p 65.chr.to_sym == :A

# a chr result is mutable, and mutating a copy must not poison the entry
p 65.chr.frozen?
t = 65.chr.dup
t << "z"
p t
p 65.chr
w = 65.chr.dup
w.setbyte(0, 66)
p w
p 65.chr

# embedded NUL through concat
b = 0.chr + 0xc8.chr
p b.length
p b.bytesize
p b[0].ord
p b[1].ord

# as Hash keys, and against a literal
h = {}
h[65.chr] = 1
h["A"] = 2
p h.size
p [65.chr, "A"].uniq.length

# the entries are static: a collection must not reach them
kept = []
2000.times do |i|
  kept.push((i % 256).chr) if (i % 97).zero?
  raise "bad" unless (i % 256).chr.bytesize == 1
end
p kept.length
p kept.map { |c| c.bytes[0] }.uniq.length
p 65.chr.bytes
