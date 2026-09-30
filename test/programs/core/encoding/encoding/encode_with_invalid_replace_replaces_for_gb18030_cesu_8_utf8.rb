def t(bytes, from, to = "UTF-8")
  r = bytes.b.force_encoding(from).encode(to, invalid: :replace)
  p [from, r]
rescue => e
  p [from, e.class, e.message]
end
t "\x81\x30", "GB18030"
t "\xED\xA0\xBDA", "CESU-8"
t "a\xFF", "UTF8-MAC"
t "a\e$Bx", "ISO-2022-JP"
t "\xFF\xFEa\x00\x00\xD8", "UTF-16"
t "\xFF\xFE\x00\x00a\x00\x00\x00\x00\xD8\x00\x00", "UTF-32"
