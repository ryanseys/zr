def t(s, to, **o)
  r = s.encode(to, **o)
  p [r.encoding.name, r.b]
rescue => e
  p [e.class, e.message, e.source_encoding_name, e.destination_encoding_name]
end
k = ->(s) { s.b.force_encoding("ISO-2022-JP-KDDI") }
t "é", "ISO-2022-JP-KDDI"
t "\u{1F4A9}", "ISO-2022-JP-KDDI"
t k["\e$BuA\e(B"], "UTF-8"
t k["\e$Bu!\e(B"], "UTF-8"
