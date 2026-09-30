# The default separator is written in the stream's encoding, and any
# other separator must be compatible with it. A separator counts only
# where a character starts.
path = "/tmp/zr_spec_utf16.txt"
File.binwrite(path, "h\x00i\x00\n\x00x\x00")
File.open(path, "rb:utf-16le") { |f| p [f.gets, f.gets].map { [_1, _1.encoding] } }
File.open(path, "rb:utf-16le") { |f| p((f.gets("\n") rescue $!)) }
File.open(path, "rb:utf-16le") { |f| p f.each_char.to_a }
File.delete(path)
def pipe(data, enc = nil)
  r, w = IO.pipe
  r.set_encoding(enc) if enc
  w.write(data.b)
  w.close
  r
end
p((pipe("ab").gets("b".encode("utf-16le")) rescue $!))
p((pipe("ab").gets("é".encode("iso-8859-1")) rescue $!))
p pipe("aéb").gets("é")
p pipe("\x82\x40\x40x", "shift_jis").gets("@")
