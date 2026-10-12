# The Encoding engine: a string is bytes + an encoding, queryable and
# transcodable, with the Encoding class and its constants. `__ENCODING__`
# answers the script encoding (UTF-8). Cross-checked against ruby.

p "hello".encoding
p __ENCODING__
p "€".bytesize
p "€".length
p "hello".ascii_only?
p "€".ascii_only?
p Encoding::UTF_8.name
p Encoding::ASCII_8BIT.names
p Encoding.find("BINARY")
p Encoding.default_external
raw = "€".b
p raw.encoding
p raw.length
mis = "€".dup.force_encoding("US-ASCII")
p mis.valid_encoding?
latin = "café".encode(Encoding::ISO_8859_1)
p latin.encoding
p latin.bytes
p latin.encode(Encoding::UTF_8) == "café"
p "café".encode(Encoding::US_ASCII, undef: :replace)
p "a<b>&c".encode(Encoding::US_ASCII, xml: :text)
begin
  "café".encode(Encoding::US_ASCII)
rescue Encoding::UndefinedConversionError => e
  puts "raised #{e.class}"
end
p :hi.encoding
p :café.encoding
