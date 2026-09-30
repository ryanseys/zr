# Encoding.compatible? takes a String, a Symbol, a Regexp, an IO or an
# Encoding, as enc_compatible_p does, and anything else answers nil.
p Encoding.default_external
p Encoding.compatible?(Encoding.default_external, "false")
p Encoding.compatible?(Encoding::UTF_8, false.inspect)
p false.inspect.encoding, 6.inspect.encoding, [1].inspect.encoding, "é".inspect.encoding
p Encoding.compatible?(Encoding::UTF_8, "x".encode("US-ASCII"))
p Encoding.compatible?(Encoding::UTF_8, "é".b)
p Encoding.compatible?(Encoding::US_ASCII, "é")
p Encoding.compatible?(Encoding::UTF_8, Encoding::US_ASCII)
p Encoding.compatible?("a", Encoding::UTF_8)
p Encoding.compatible?(Encoding::UTF_16LE, "a")
p Encoding.compatible?(:sym, "é"), Encoding.compatible?(/a/, "é".encode("ISO-8859-1")), Encoding.compatible?(STDOUT, "x"), Encoding.compatible?(1, "x")
p Encoding.compatible?("é", "ü".encode("ISO-8859-1")), Encoding.compatible?("a".b, "é"), Encoding.compatible?("é".b, "a"), Encoding.compatible?("", "é".b)
p Encoding.compatible?(Encoding::UTF_8, Encoding::ISO_8859_1), Encoding.compatible?(Encoding::UTF_16LE, Encoding::UTF_8)


