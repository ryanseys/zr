s = +"héllo wörld"
s[1] = "E"; p s
s[0, 3] = "日本"; p s, s.encoding, s.valid_encoding?
s[-5..] = "!"; p s
s["!"] = "?!?"; p s
begin; s[/(ll)/, 1] = "LL"; rescue => e; p e.class; end
p s
t = +"abc"; t[1, 1] = t; p t
u = +"x"; 20.times { |i| u[u.bytesize, 0] = "ab#{i}" }; p u, u.bytesize
b = ("\0" * 16).b; b[4, 4] = [0xdeadbeef].pack("L<"); p b.bytes
begin; b[0, 0] = "é"; p b.encoding, b.bytesize; rescue => e; p e.class; end
ascii = +"plain"; ascii[0] = "ü"; p ascii, ascii.encoding
begin; "frozen".freeze[0] = "x"; rescue => e; p e.class; end
begin; bin = "\xff".b.dup; bin[0, 0] = "é"; p bin, bin.encoding; rescue => e; p e.class, e.message; end
begin; x = +"é"; x[0, 0] = "\xff".b; p x; rescue => e; p e.class, e.message; end
v = +"hello"; p v.insert(2, "XY"), v.insert(-1, "!"), v.insert(0, v)
w = +"abc"; w[3, 0] = "d"; w[1, 5] = ""; p w
begin; (+"ab")[5] = "x"; rescue => e; p e.class, e.message; end
e = "".encode("UTF-16LE"); e[0, 0] = "a".encode("UTF-16LE"); p e.bytes


