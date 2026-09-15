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

__END__
#<Encoding:UTF-8>
nil
"ISO-8859-1"
#<Encoding:ISO-8859-1>
#<Encoding:ISO-8859-1>
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
["UTF-8", "CP65001", "locale"]
["ISO-8859-1", "ISO8859-1", "external", "filesystem"]
["ISO-8859-1", "ISO-8859-1", "UTF-8", nil]
#<Encoding:ISO-8859-1>
6
#<Encoding:ISO-8859-1>
#<Encoding:ISO-8859-1>
#<Encoding:ISO-8859-1>
nil
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
#<Encoding:UTF-8>
#<Encoding:UTF-8>
["UTF-8", "CP65001", "locale", "internal"]
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
#<Encoding:UTF-8>
[99, 97, 102, 195, 131, 194, 169, 10]
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
"\xE9"
#<Encoding:BINARY (ASCII-8BIT)>
nil
#<Encoding:BINARY (ASCII-8BIT)>
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
nil
nil
nil
1
#<ArgumentError: default external can not be nil>
#<ArgumentError: unknown encoding name - nope>
#<TypeError: no implicit conversion of Integer into String>
#<Encoding:UTF-8>
#<Encoding:UTF-8>
#<Encoding:ISO-8859-1>
#<Encoding:UTF-8>
1
"\xE9"
"\xE9"
"\xFF"
#<Encoding:EUC-JP>
"a\xFF&lt;"
"a\uFFFD"
#@ stderr
core/encoding/the_default_encodings_are_settable.rb:53: warning: setting Encoding.default_external
core/encoding/the_default_encodings_are_settable.rb:54: warning: setting Encoding.default_internal
core/encoding/the_default_encodings_are_settable.rb:55: warning: setting Encoding.default_external
core/encoding/the_default_encodings_are_settable.rb:56: warning: setting Encoding.default_internal
core/encoding/the_default_encodings_are_settable.rb:61: warning: setting Encoding.default_internal
core/encoding/the_default_encodings_are_settable.rb:64: warning: setting Encoding.default_internal
