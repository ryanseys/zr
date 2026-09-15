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


__END__
"hEllo wörld"
"日本lo wörld"
#<Encoding:UTF-8>
true
"日本lo !"
"日本lo ?!?"
IndexError
"日本lo ?!?"
"aabcc"
"xab0ab1ab2ab3ab4ab5ab6ab7ab8ab9ab10ab11ab12ab13ab14ab15ab16ab17ab18ab19"
71
[0, 0, 0, 0, 239, 190, 173, 222, 0, 0, 0, 0, 0, 0, 0, 0]
Encoding::CompatibilityError
"ülain"
#<Encoding:UTF-8>
FrozenError
Encoding::CompatibilityError
"incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"
Encoding::CompatibilityError
"incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"
"heXYllo!heXYllo!"
"heXYllo!heXYllo!"
"heXYllo!heXYllo!"
"a"
IndexError
"index 5 out of string"
[97, 0]
