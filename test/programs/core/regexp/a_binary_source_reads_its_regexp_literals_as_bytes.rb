# encoding: binary
# A regexp literal with no flag letter reads its pattern in the source's
# encoding, so a \xAA escape is a byte in a binary file; an ASCII pattern
# is still US-ASCII. Interpolation starts in the source's encoding too.
p(/\xAA/.match("\nA"))
p(/\xAA/.encoding, /\xAA/.source.encoding)
p(/\xAA/ =~ "\xAA".b)
p(/abc/.encoding, /\xA/.match("\nxyz").to_a, /\x0AA/.match("\nA").to_a, /\xAG/.match("\nG").to_a)
x = "q"
p(/a#{x}/.encoding, /\xAA#{x}/.encoding)
x = "b"
p "a#{x}c".encoding
a = "abc".dup.force_encoding("euc-jp")
p "#{a}".encoding
b = "abc".encode("utf-8")
p "#{b}".encoding
p "#{b}x".encoding
p "a#{"b"}c".encoding
p eval(%q("a#{"b"}c").dup.force_encoding("us-ascii")).encoding
p eval("__ENCODING__".dup.force_encoding("US-ASCII"))
p eval("__ENCODING__".dup.force_encoding("BINARY"))
make_regexp = -> str { /#{str}/ }
r = make_regexp.call("\xC3\xA9t\xC3\xA9".dup.force_encoding(Encoding::UTF_8))
p r.fixed_encoding?, r.encoding
r = make_regexp.call("abc".dup.force_encoding(Encoding::UTF_8))
p r.fixed_encoding?, r.encoding
x = "q"
