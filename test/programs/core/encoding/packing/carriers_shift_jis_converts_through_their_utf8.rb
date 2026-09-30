
# Ruby converts SJIS-DoCoMo, SJIS-KDDI, SJIS-SoftBank and
# stateless-ISO-2022-JP-KDDI through the carrier's own UTF-8, whose emoji
# are private-use code points: an emoji with no Unicode one still crosses
# between them, and a failure names each step.
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

