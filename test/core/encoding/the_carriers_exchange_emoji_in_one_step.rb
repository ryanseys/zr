# The carriers' UTF-8 encodings exchange their emoji with each other and
# with Unicode in one step, and a failure words them as ruby does.
def t(s, to, **o)
  r = s.encode(to, **o)
  p [r.encoding.name, r.b]
rescue => e
  p [e.class, e.message, (e.error_bytes rescue nil), (e.error_char rescue nil), (e.source_encoding_name rescue nil), (e.destination_encoding_name rescue nil)]
end
d = ->(s) { s.b.force_encoding("UTF8-DoCoMo") }
k = ->(s) { s.b.force_encoding("UTF8-KDDI") }
t "\u{1F4A9}", "UTF8-DoCoMo"
t d["\u{E6A0}"], "UTF-8"
t d["\u{E6A0}"], "UTF8-KDDI"
t d["\u{E6A0}"], "UTF8-KDDI", undef: :replace
t d["\u{E6A0}"], "EUC-JP"
t d["\u{E63E}"], "EUC-JP"
t d["\u{E63E}"], "Shift_JIS"
t d["a\xFFb"], "UTF-8"
t d["a\xFFb"], "UTF8-KDDI"
t d["a\xE3\x81"], "UTF8-KDDI"
t "a\xFFb", "UTF8-KDDI"
t "a\xFF\u{1F4A9}", "UTF8-KDDI", invalid: :replace, undef: :replace
t "\u{1F4A9}", "UTF8-DoCoMo", undef: :replace, replace: "X"
t "\u{1F4A9}", "UTF8-DoCoMo", fallback: {"\u{1F4A9}" => "P"}
t "日\u{2600}", "UTF8-SoftBank", xml: :text
t "\u{1F4A9}<", "UTF8-DoCoMo", xml: :text
t k["\u{E488}\u{E4F5}"], "UTF-8"

__END__
[Encoding::UndefinedConversionError, "U+1F4A9 from UTF-8 to UTF8-DoCoMo", nil, "💩", "UTF-8", "UTF8-DoCoMo"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" from UTF8-DoCoMo to UTF-8", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" from UTF8-DoCoMo to UTF8-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
["UTF8-KDDI", "?"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from UTF8-DoCoMo to UTF-8 to EUC-JP", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
[Encoding::UndefinedConversionError, "U+2600 to EUC-JP in conversion from UTF8-DoCoMo to UTF-8 to EUC-JP", nil, "☀", "UTF-8", "EUC-JP"]
[Encoding::UndefinedConversionError, "U+2600 to Shift_JIS in conversion from UTF8-DoCoMo to UTF-8 to Shift_JIS", nil, "☀", "UTF-8", "Shift_JIS"]
[Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF8-DoCoMo", "\xFF", nil, "UTF8-DoCoMo", "UTF-8"]
[Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF8-DoCoMo", "\xFF", nil, "UTF8-DoCoMo", "UTF8-KDDI"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\xE3\\x81\" on UTF8-DoCoMo", "\xE3\x81", nil, "UTF8-DoCoMo", "UTF8-KDDI"]
[Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF-8", "\xFF", nil, "UTF-8", "UTF8-KDDI"]
["UTF8-KDDI", "a?\xEE\x93\xB5"]
["UTF8-DoCoMo", "X"]
["UTF8-DoCoMo", "P"]
["UTF8-SoftBank", "\xE6\x97\xA5\xEE\x81\x8A"]
["UTF8-DoCoMo", "&#x1F4A9;&lt;"]
[Encoding::UndefinedConversionError, "\"\\xEE\\x93\\xB5\" from UTF8-KDDI to UTF-8", nil, "\uE4F5", "UTF8-KDDI", "UTF-8"]
