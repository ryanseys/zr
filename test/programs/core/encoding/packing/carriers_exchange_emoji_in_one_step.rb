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

