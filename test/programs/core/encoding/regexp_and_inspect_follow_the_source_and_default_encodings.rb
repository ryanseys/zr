# In a US-ASCII source a regexp with a byte past ASCII is binary, and an
# inspect inside an Array keeps text in the default internal encoding.
src = "# -*- encoding: US-ASCII -*-\n/\\x80/.encoding"
p eval(src.dup.force_encoding("US-ASCII"))
p eval("/a/".dup.force_encoding("US-ASCII")).encoding
s = "\xB4\xC1\xBB\xFA".dup.force_encoding("EUC-JP")
$VERBOSE = nil
Encoding.default_internal = Encoding::EUC_JP
t = [s].inspect
Encoding.default_internal = nil
p t.encoding, t.b, [s].inspect
