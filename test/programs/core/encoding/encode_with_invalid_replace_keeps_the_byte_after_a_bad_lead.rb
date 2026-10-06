def t(bytes, from)
  r = bytes.b.force_encoding(from).encode("UTF-8", invalid: :replace)
  p [from, r]
rescue => e
  p [from, e.class, e.message]
end
t "\x81\x30", "Shift_JIS"
t "\x81\x7F", "GBK"
t "\xA1\x30", "Big5"
t "\x81\x30", "CP949"
t "\xA1\x30", "EUC-JP"
t "\xA1\x30", "EUC-KR"
t "\x81\x30", "Windows-31J"
