# `s[i]` on a BINARY string gives a 1-byte string that keeps the ASCII-8BIT
# encoding. zr takes it from a shared static table, so it does not allocate.
# Each entry has its real length, so byte 0 gives "\x00", not an empty string.

b = [200, 65, 0, 255].pack("C*")
p b.bytesize
p b[0].bytes
p b[1].bytes
p b[2].bytes
p b[3].bytes
p b[0].encoding.to_s
p b[1].encoding.to_s
p b[0].length
p b[2].length
p b[2].bytesize
p b[0] == b[0]
p b[1] == "A"
p b[0].inspect
p b[2].inspect

# the slice is not frozen, and mutating a copy must not poison the shared entry
x = b[1]
p x.frozen?
y = x.dup
y << "z"
p y
p b[1].bytes
p b[1] == "A"

w2 = b[1].dup
w2.setbyte(0, 66)
p w2.bytes
p b[1].bytes

# as Hash keys
h = {}
h[b[0]] = 1
h[b[1]] = 2
p h.size
p h[b[0]]

# the entries survive collection: they are static, so the mark must skip them
kept = []
2000.times do |i|
  kept.push(b[i % 4]) if (i % 97).zero?
  raise "bad" unless b[i % 4].bytesize == 1
end
p kept.length
p kept.map { |c| c.bytes[0] }.uniq.sort
p b.bytes

# and the ASCII table is untouched
s = String.new("abc")
p s[1]
p s[1].encoding.to_s
p s[1] == "b"
p s[1].frozen?
