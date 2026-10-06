# GB18030 holds every Unicode character: the ones a two-byte row
# does not name take four bytes, whether or not they are past the
# BMP. CESU-8 writes a character past the BMP as its two
# surrogates, three bytes each, where UTF-8 writes four.
def bytes(text, name) = text.encode(name).bytes.map { |b| b.to_s(16) }

p bytes("\u{10000}", "GB18030")
p bytes("\u{20BB7}", "GB18030")
p bytes("\u{4E00}", "GB18030")
p bytes("\u{00A5}", "GB18030")
p "\u{20BB7}\u{4E00}A".encode("GB18030").length
p "\u{20BB7}A".encode("GB18030").each_char.map(&:bytesize)
p "\u{20BB7}\u{4E00}A".encode("GB18030").encode("UTF-8")
p "\x95\x32\x82\x36".dup.force_encoding("GB18030").encode("UTF-8").ord.to_s(16)

p bytes("\u{10000}", "CESU-8")
p bytes("\u{4E00}", "CESU-8")
p "\u{10000}A".encode("CESU-8").length
p "\u{1D11E}x".encode("CESU-8").encode("UTF-8")
p "\xED\xA0\x80\xED\xB0\x80".dup.force_encoding("CESU-8").encode("UTF-8").ord.to_s(16)
