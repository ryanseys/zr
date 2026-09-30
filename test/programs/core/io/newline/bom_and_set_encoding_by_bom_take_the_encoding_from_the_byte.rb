# "bom|" lets the byte order mark give the encoding and takes it out of
# the stream. set_encoding_by_bom does the same for a binary stream with
# no encoding of its own, and knows UTF-8, UTF-16 and UTF-32.
path = "/tmp/zr_spec_bom.txt"
File.binwrite(path, "\xEF\xBB\xBFhi")
File.open(path, "r:bom|utf-8") { |f| p [f.read, f.external_encoding] }
File.binwrite(path, "\xFF\xFEh\x00i\x00")
File.open(path, "rb:bom|utf-16le:utf-8") { |f| p f.read }
File.binwrite(path, "\xFE\xFF\x00h")
File.open(path, "rb:BOM|utf-8") { |f| p [f.read, f.external_encoding] }
File.binwrite(path, "hi")
File.open(path, "r:bom|utf-8") { |f| p [f.read, f.external_encoding] }
File.binwrite(path, "\xEF\xBB\xBFhi")
File.open(path, "rb") { |f| p [f.set_encoding_by_bom, f.read, f.external_encoding] }
File.binwrite(path, "\xFF\xFE\x00\x00h\x00\x00\x00")
File.open(path, "rb") { |f| p [f.set_encoding_by_bom, f.read] }
File.binwrite(path, "\xEF\xBB\xBFhi")
File.open(path) { |f| p((f.set_encoding_by_bom rescue $!)) }
File.open(path, "rb") { |f| f.set_encoding_by_bom; p((f.set_encoding_by_bom rescue $!)) }
File.open(path, "rb:utf-8") { |f| p((f.set_encoding_by_bom rescue $!)) }
r, w = IO.pipe
r.binmode
w.write("\xFF\xFEa\x00")
w.close
p [r.set_encoding_by_bom, r.read]
File.delete(path)
