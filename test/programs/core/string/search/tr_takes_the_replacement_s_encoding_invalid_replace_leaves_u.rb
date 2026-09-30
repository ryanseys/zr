x = "hello".b.tr("h", "é")
p x, x.encoding
p "hello".b.tr("é", "x").encoding
begin
  "é".encode("US-ASCII", invalid: :replace)
rescue Encoding::UndefinedConversionError => e
  p e.message
end
p "a\xff".encode(invalid: :replace)
p "\xe3\x81".scrub, "\xf0\x9f\x98a".scrub("?"), "a\xe3\x81\x81\xe3\x81b".scrub("*")
