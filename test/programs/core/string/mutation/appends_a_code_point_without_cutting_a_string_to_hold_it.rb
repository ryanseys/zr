# `s << byte` writes the byte where it goes when the receiver's
# characters are bytes, and spells a code point in UTF-8 when they are
# not. rb_str_concat keeps the plain-ASCII flag, turns a US-ASCII
# receiver binary at the first byte past ASCII, and refuses a byte
# above 255 on a binary one.
s = +"".b
s << 65 << 200 << 0
p s, s.encoding, s.bytes
u = +"ab"
u << 233
p u, u.encoding, u.valid_encoding?
w = +"ab"
w << 0x1F600
p w, w.encoding, w.bytes.size
a = +"ab".force_encoding("US-ASCII")
a << 200
p a, a.encoding
b = +"ab".force_encoding("US-ASCII")
b << 65
p b, b.encoding
e = +"".force_encoding("EUC-JP")
e << 0xA4A2
p e.bytes, e.encoding
begin; (+"a".b) << 256; rescue RangeError => x; puts x.message; end
big = +"x" * 300
300.times { |i| big << (i % 256) }
p big.bytesize, big.getbyte(300), big.getbyte(599)
asc = +"abc"
p asc.ascii_only?
asc << 65
p asc.ascii_only?
asc << 200
p asc.ascii_only?, asc.encoding
# Array#pack writes every byte of an integer that way.
p [0x12345678].pack("L<").bytes, [0x12345678].pack("L>").bytes
p (1..6).to_a.pack("Q<*").bytesize, [-1].pack("q>").bytes
