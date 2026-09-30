# A converter keeps the bytes it must read again after a broken
# character: its errinfo, the error and putback give them, and the
# message says what followed.
def show(from, to, src)
  ec = Encoding::Converter.new(from, to)
  s = src.dup.force_encoding(from)
  d = +""
  r = ec.primitive_convert(s, d)
  [r, s, ec.primitive_errinfo, ec.putback, ec.last_error&.message, ec.last_error&.readagain_bytes]
end
p show("UTF-8", "ISO-8859-1", "\xf1abcd")
p show("UTF-8", "ISO-8859-1", "\xffab")
p show("UTF-8", "ISO-8859-1", "a\xf0\x90\x80b")
p show("EUC-JP", "UTF-8", "\xa4\x41b")
p show("UTF-16LE", "UTF-8", "\x00\xd8a\x00")
p show("UTF-8", "EUC-JP", "\xed\xa0\x80z")
p(("\xf1abc".encode("iso-8859-1") rescue $!), ("\xe3\x81a".encode("utf-16le") rescue $!))
