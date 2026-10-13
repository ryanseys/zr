# ruby 4.1's Onigmo gives a single-byte encoding no code point past a
# byte. Integer#chr and String#<< name the code and the encoding, %c
# says "invalid character", and a binary or US-ASCII String keeps its
# "out of char range".
def t; p yield; rescue => e; p [e.class, e.message]; end
t { "a".b << 300 }
t { "a".force_encoding("ISO-8859-1") << 300 }
t { "a".force_encoding("US-ASCII") << 300 }
t { "a".force_encoding("Windows-1252") << 256 }
t { "a".b.concat(256) }
t { ("%c".force_encoding("ISO-8859-1")) % 300 }
t { ("%c".b) % 300 }
t { 300.chr(Encoding::IBM437) }
t { 256.chr(Encoding::KOI8_R) }
t { 300.chr(Encoding::ISO_8859_1) }
t { 256.chr(Encoding::BINARY) }
t { 128.chr(Encoding::US_ASCII) }
t { 256.chr(Encoding::US_ASCII) }
t { 255.chr(Encoding::ISO_8859_1).bytes }
t { 0x7F.chr(Encoding::US_ASCII) }
t { "a".force_encoding("ISO-8859-1").freeze << 300 }
t { s = "a".force_encoding("KOI8-U"); s << 255; [s.bytes, s.encoding] }
t { "a".force_encoding("Shift_JIS") << 300 }
t { "a".force_encoding("EUC-JP") << 0x10000 }
t { ("%c".force_encoding("Windows-1251")) % 255 }
t { ("%c".force_encoding("US-ASCII")) % 200 }
t { ("%-3c|".force_encoding("ISO-8859-5")) % 256 }

# The code is checked before the String's frozen state.
t { "a".b.freeze << 300 }
t { "a".b.freeze << 200 }
t { "a".freeze << 0x110000 }
t { "a".freeze << 0xD800 }
t { "a".freeze << 0x41 }
t { "a".force_encoding("ISO-8859-1").freeze << 200 }
t { "a".force_encoding("EUC-JP").freeze << 0x10000 }
t { "a".encode("UTF-16LE").freeze << 0x110000 }
t { "a".encode("UTF-16LE").freeze << 0x41 }
