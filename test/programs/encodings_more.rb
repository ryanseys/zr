# native only
# Every single-byte encoding rides on a String, through comparison,
# joining, case mapping, regexp matching and conversion by way of
# UTF-8.
l = "caf\xe9".force_encoding("ISO-8859-1")
w = "\x81ab".force_encoding("Windows-1252")
p l, l.encoding, l.size, l.bytes, l.valid_encoding?, l.ascii_only?
p w, w.valid_encoding?, w.size

p l == "caf\xe9".b, l == "caf\xe9".force_encoding("ISO-8859-1"), l.hash == "caf\xe9".b.hash
p({ l => 1 }["caf\xe9".b], { l => 1 }[l])

p ("x" + l).encoding, (l + "x").encoding, (l * 2).bytes
p "abc#{l}".encoding, "#{1}#{l}".encoding
[[l, "é"], ["é", l], [l, "\xe9".b]].each do |a, b|
  a + b
rescue Encoding::CompatibilityError => e
  puts e.message
end

p l.upcase.bytes, l.downcase.bytes, l.capitalize.bytes, l.swapcase.bytes
p "stra\xdfe".force_encoding("ISO-8859-1").upcase.bytes
koi = "\xc1z".force_encoding("KOI8-R")
p koi.upcase.bytes
p l.reverse.bytes, "caf\xc3\xa9".b.reverse.bytes

p(/(.)/.match(l)[1].encoding, l[/af./].bytes, l.split(/f/).map(&:encoding))
begin
  /é/.match(l)
rescue Encoding::CompatibilityError => e
  puts e.message
end

p "żół".encode("Windows-1250").bytes
p "é".encode("ISO-8859-1").bytes, "\xe9".force_encoding("ISO-8859-1").encode("UTF-8").bytes
p "\xe9".force_encoding("ISO-8859-1").encode("ISO-8859-15").bytes
[["ż", "ISO-8859-1"], ["\x81".force_encoding("Windows-1252"), "UTF-8"],
 ["\x81".force_encoding("Windows-1252"), "KOI8-R"], ["é", "US-ASCII"]].each do |text, target|
  text.encode(target)
rescue Encoding::UndefinedConversionError => e
  puts e.message
end
p "ż".encode("ISO-8859-1", undef: :replace), "ż".encode("ISO-8859-1", undef: :replace, replace: "!")
begin
  "x".encode("GB1988")
rescue Encoding::ConverterNotFoundError => e
  puts e.message
end

p "a\nb\r\nc\rd".encode("UTF-8", newline: :cr), "a\nb".encode("UTF-8", newline: :crlf)
p "a\r\nb".encode("UTF-8", universal_newline: true)

p format("%s", l).encoding, format("%d".b, 5).encoding
p "caf".ljust(6, l).bytes, "caf".ljust(6, l).encoding
begin
  "café".ljust(8, l)
rescue Encoding::CompatibilityError => e
  puts e.message
end

p Encoding.find("cp1250"), Encoding::CP1252 == Encoding::Windows_1252
p Encoding.list.size, Encoding.compatible?(l, "x"), Encoding.compatible?(l, "é")
p 0xE9.chr(Encoding::ISO_8859_1).bytes, 0xE9.chr(Encoding::ISO_8859_1).encoding
