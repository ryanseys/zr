# Encoding.default_external= and default_internal= set what a stream that
# names no encoding reads and converts to, what "external", "filesystem"
# and "internal" name, and what a bare String#encode converts to.

path = "the_default_encodings_are_settable.txt"
File.binwrite(path, "caf\xC3\xA9\n")
p Encoding.default_external, Encoding.default_internal
a = File.open(path)
p Encoding.default_external = "ISO-8859-1"
p Encoding.default_external
p Encoding.find("external"), Encoding.find("filesystem"), Encoding.find("locale")
p Encoding::UTF_8.names, Encoding::ISO_8859_1.names
p Encoding.aliases.values_at("external", "filesystem", "locale", "internal")
s = File.read(path)
p s.encoding, s.bytes.size
p a.external_encoding, a.read.encoding
a.close
File.open(path) { |f| p f.external_encoding, f.internal_encoding, f.gets.encoding }
p Encoding.default_internal = Encoding::UTF_8
p Encoding.default_internal, Encoding.find("internal")
p Encoding::UTF_8.names
File.open(path) do |f|
  p f.external_encoding, f.internal_encoding
  line = f.gets
  p line.encoding, line.bytes
end
File.open(path, "w") { |f| p f.external_encoding, f.internal_encoding; f.write "é" }
p File.binread(path)
File.open(path, "r:BINARY") { |f| p f.external_encoding, f.internal_encoding, f.read.encoding }
File.open(path, "r:ISO-8859-1") { |f| p f.external_encoding, f.internal_encoding }
p Encoding.default_internal = nil
p Encoding.find("internal"), Encoding.aliases["internal"], Encoding.name_list.count("internal")
begin
  Encoding.default_external = nil
rescue => e
  p e
end
begin
  Encoding.default_external = "nope"
rescue => e
  p e
end
begin
  Encoding.default_internal = 1
rescue => e
  p e
end
p "x".encode.encoding
Encoding.default_external = Encoding::UTF_8
p File.read(path).encoding
File.delete(path)
$VERBOSE = true
Encoding.default_external = "UTF-8"
Encoding.default_internal = nil
Encoding.default_external = "ISO-8859-1" if true
Encoding.default_internal = Encoding::UTF_8
File.open("the_default_encodings_are_settable_2.txt", "w") { |f| p f.external_encoding, f.internal_encoding; p f.write("é"); p "é".encode(f.external_encoding) }
p File.binread("the_default_encodings_are_settable_2.txt")
File.delete("the_default_encodings_are_settable_2.txt")
s = "\xff".force_encoding("EUC-JP")
Encoding.default_internal = nil
p s.encode, s.encode.encoding
p "a\xff<".encode(xml: :text)
Encoding.default_internal = "UTF-16LE"
p "a\xff".encode

