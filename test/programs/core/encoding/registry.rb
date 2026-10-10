# The encoding registry: every name ruby knows, its constants, and the
# three a String can carry.
p Encoding.list.size, Encoding.constants.size, Encoding::UNICODE_VERSION
p Encoding::UTF_8, Encoding::BINARY, Encoding::ASCII_8BIT.name
p Encoding::EUC_JP, Encoding.find("EUC-JP"), Encoding::EUC_JP
p Encoding.find("Shift_JIS"), Encoding.find("binary"), Encoding.find(Encoding::UTF_8)
begin
  Encoding.find("nope")
rescue ArgumentError => e
  puts e.message
end
p Encoding.aliases.size, Encoding.aliases["BINARY"], Encoding.name_list.size
p Encoding.locale_charmap, Encoding.default_external, Encoding.default_internal
p Encoding::UTF_16BE.ascii_compatible?, Encoding::UTF_8.ascii_compatible?
p Encoding::ISO_2022_JP.dummy?, Encoding::UTF_8.dummy?
p "x".encoding, "x".b.encoding, "x".force_encoding("US-ASCII").encoding
p Encoding.compatible?("a", "b".b), Encoding.compatible?("é", "b".b)
