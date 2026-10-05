# A suffix counts only from the head of a character, in UTF-8, in a
# multibyte encoding and in UTF-16; a binary String has a head at each
# byte. force_encoding("internal") is BINARY while it is unset.
p "\xC3\xA9".end_with?("\xA9"), "\xe3\x81\x82".end_with?("\x82")
p "\xd8\x00\xdc\x00".dup.force_encoding("UTF-16BE").end_with?("\xdc\x00".dup.force_encoding("UTF-16BE"))
p "\xC3\xA9".b.end_with?("\xA9".b), "abc".encode("UTF-16LE").end_with?("c".encode("UTF-16LE"))
p "\xC3\xA9".b.byteindex("\xA9".b), "あい".encode("EUC-JP").byteindex("い".encode("EUC-JP"))
p :"\xd8\x00\xdc\x00".end_with?("x")
Encoding.default_internal = nil
p "abc".force_encoding("internal").encoding
Encoding.default_internal = "US-ASCII"
p "abc".force_encoding("internal").encoding
Encoding.default_internal = nil
