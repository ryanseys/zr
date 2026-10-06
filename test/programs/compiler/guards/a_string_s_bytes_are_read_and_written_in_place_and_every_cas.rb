# The bytes read and written where they stand: a loop over a copy, the
# scans forgotten after a write, a chilled literal, a subclass, a frozen
# String, the ends of the range, and a MatchData taken before the write.
s = "hello".dup
i = 0
while i < s.bytesize
  s.setbyte(i, s.getbyte(i) - 32)
  i += 1
end
p s
t = "abc".dup
p t.ascii_only?, t.valid_encoding?
t.setbyte(1, 0xff)
p t.ascii_only?, t.valid_encoding?, t.bytes
t.setbyte(1, 0x62 - 256)
p t, t.ascii_only?
lit = "xyz"
lit.setbyte(0, 0x58)
p lit
class Bytes < String
  def getbyte(i) = -1
end
b = Bytes.new("ab")
p b.getbyte(0), b.setbyte(0, 0x41), b
m = "abc".dup
md = m.match(/b/)
m.setbyte(1, 0x42)
p md[0], md.pre_match, md.string, m
f = "abc".freeze
begin
  f.setbyte(0, 1)
rescue FrozenError => e
  p e.message
end
e = "ab".dup
p e.getbyte(2), e.getbyte(-2), e.getbyte(-3), e.setbyte(-2, 0x7a), e
begin
  e.setbyte(2, 1)
rescue IndexError => x
  p x.message
end
begin
  e.setbyte(0, 1.5)
rescue TypeError => x
  p x.class
end
p e.setbyte(0, 2**64 + 0x41), e
h = "été".dup
p h.getbyte(0), h.getbyte(1), h.length
h.setbyte(0, 0x41)
p h.length, h.valid_encoding?
p e.setbyte(1, -(2**64) + 0x42), e, e.setbyte(1.9, 0x43), e
[[5, 1], [0, nil], [nil, 1], [0, Object.new]].each do |at, byte|
  "x".freeze.setbyte(at, byte)
rescue IndexError, TypeError, FrozenError => x
  p x
end
