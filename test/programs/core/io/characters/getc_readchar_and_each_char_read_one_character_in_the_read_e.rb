# getc, readchar and each_char read one character in the read encoding:
# the external one, binary under "rb", and the internal one after a
# conversion.
path = "/tmp/zr_spec_chars.txt"
File.binwrite(path, "aéあ")
File.open(path) { |f| p [f.getc, f.getc, f.readchar, f.getc].map { [_1, _1&.encoding] } }
File.open(path, "rb") { |f| p f.each_char.to_a }
File.open(path, "r:BINARY") { |f| p [f.getc, f.external_encoding] }
File.open(path, "r:iso-8859-1") { |f| p f.each_char.first(3) }
File.open(path, "r:iso-8859-1:utf-8") { |f| p f.each_char.to_a }
File.open(path, "rb:utf-8") { |f| p f.getc }
File.delete(path)
