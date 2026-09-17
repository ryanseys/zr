#@ skip: the carrier tables hold Unicode's code points, so an emoji with no Unicode one stops mid-conversion
# Ruby converts SJIS-DoCoMo, SJIS-KDDI, SJIS-SoftBank and
# stateless-ISO-2022-JP-KDDI through the carrier's own UTF-8, whose emoji
# are private-use code points: an emoji with no Unicode one still crosses
# between them, and a failure names each step. This runtime's tables for
# them hold Unicode's code points, read through UTF-8, so such an emoji
# stops, and a failure names one step.
def t(s, to, **o)
  r = s.encode(to, **o)
  p [r.encoding.name, r.b]
rescue => e
  p [e.class, e.message, (e.error_bytes rescue nil), (e.error_char rescue nil), e.source_encoding_name, e.destination_encoding_name]
end
full_moon = "\u{E6A0}".encode("UTF8-DoCoMo", "UTF-8").encode("SJIS-DoCoMo")
p full_moon.b
t full_moon, "UTF-8"
t full_moon, "UTF8-DoCoMo"
t full_moon, "UTF8-KDDI"
t full_moon, "EUC-JP"
t full_moon, "SJIS-KDDI"
t "\u{1F4A9}", "SJIS-DoCoMo"
t "é", "SJIS-DoCoMo"
t "é", "SJIS-KDDI"
t "é", "SJIS-SoftBank"
t "\xFF".b.force_encoding("SJIS-DoCoMo"), "UTF-8"
t "\x81".b.force_encoding("SJIS-DoCoMo"), "UTF-8"
t "é".encode("EUC-JP"), "SJIS-DoCoMo" rescue p $!
t "ア".encode("EUC-JP"), "SJIS-DoCoMo"
t "\u{E6A0}".b.force_encoding("UTF8-DoCoMo"), "SJIS-DoCoMo"
t "\u{E6A0}".b.force_encoding("UTF8-DoCoMo"), "stateless-ISO-2022-JP-KDDI"
t "é", "stateless-ISO-2022-JP-KDDI"
t "\u{1F4A9}", "stateless-ISO-2022-JP-KDDI"
t "\x92\xF5\xC1".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "UTF-8"
t "\x92\xFF\xC1".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "UTF-8"
t "é", "SJIS-DoCoMo", undef: :replace
t full_moon, "UTF-8", undef: :replace
t full_moon, "UTF-8", fallback: ->(c) { p [c.encoding, c.b]; "M" }
t "é", "SJIS-DoCoMo", fallback: ->(c) { p [c.encoding, c.b]; "E" }
t "ア".encode("SJIS-KDDI"), "SJIS-DoCoMo"
[full_moon, "日".encode("SJIS-DoCoMo")].each { |s| p Encoding::Converter.new(s.encoding, "UTF-8").convpath }
p Encoding::Converter.search_convpath("SJIS-KDDI", "SJIS-DoCoMo")
p Encoding::Converter.search_convpath("stateless-ISO-2022-JP-KDDI", "SJIS-KDDI")

__END__
"\xF9D"
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF-8", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
["UTF8-DoCoMo", "\xEE\x9A\xA0"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF8-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF-8 to EUC-JP", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF8-KDDI to SJIS-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
[Encoding::UndefinedConversionError, "U+1F4A9 to UTF8-DoCoMo in conversion from UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "💩", "UTF-8", "UTF8-DoCoMo"]
[Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-DOCOMO in conversion from UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "\u00E9", "UTF8-DOCOMO", "SJIS-DOCOMO"]
[Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-KDDI in conversion from UTF-8 to UTF8-KDDI to SJIS-KDDI", nil, "\u00E9", "UTF8-KDDI", "SJIS-KDDI"]
[Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-SoftBank in conversion from UTF-8 to UTF8-SoftBank to SJIS-SoftBank", nil, "\u00E9", "UTF8-SoftBank", "SJIS-SoftBank"]
[Encoding::InvalidByteSequenceError, "\"\\xFF\" on SJIS-DOCOMO", "\xFF", nil, "SJIS-DOCOMO", "UTF8-DOCOMO"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\x81\" on SJIS-DOCOMO", "\x81", nil, "SJIS-DOCOMO", "UTF8-DOCOMO"]
[Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-DOCOMO in conversion from EUC-JP to UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "\u00E9", "UTF8-DOCOMO", "SJIS-DOCOMO"]
["SJIS-DoCoMo", "\x83A"]
["SJIS-DoCoMo", "\xF9D"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from UTF8-DoCoMo to UTF8-KDDI to stateless-ISO-2022-JP-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
[Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to stateless-ISO-2022-JP-KDDI in conversion from UTF-8 to UTF8-KDDI to stateless-ISO-2022-JP-KDDI", nil, "\u00E9", "UTF8-KDDI", "stateless-ISO-2022-JP-KDDI"]
["stateless-ISO-2022-JP-KDDI", "\x92\xF6\xD0"]
["UTF-8", "\xE2\x98\x80"]
[Encoding::InvalidByteSequenceError, "\"\\x92\" followed by \"\\xFF\" on stateless-ISO-2022-JP-KDDI", "\x92", nil, "stateless-ISO-2022-JP-KDDI", "UTF8-KDDI"]
["SJIS-DoCoMo", "?"]
["UTF-8", "\xEF\xBF\xBD"]
[#<Encoding:UTF8-DoCoMo>, "\xEE\x9A\xA0"]
["UTF-8", "M"]
[#<Encoding:UTF8-DoCoMo>, "\xC3\xA9"]
["SJIS-DoCoMo", "E"]
["SJIS-DoCoMo", "\x83A"]
[[#<Encoding:SJIS-DoCoMo>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:UTF-8>]]
[[#<Encoding:SJIS-DoCoMo>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:UTF-8>]]
[[#<Encoding:SJIS-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:SJIS-DoCoMo>]]
[[#<Encoding:stateless-ISO-2022-JP-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:SJIS-KDDI>]]
