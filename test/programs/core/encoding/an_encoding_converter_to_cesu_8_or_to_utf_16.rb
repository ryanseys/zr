def t(from, to, s)
  c = Encoding::Converter.new(from, to)
  r = c.convert(s) + c.finish
  p [to, r.b]
rescue => e
  p [to, e.class, e.message]
end
t "UTF-8", "CESU-8", "日"
t "UTF-8", "CESU-8", "\u{1F600}"
t "UTF-8", "UTF-16", "a"
t "UTF-8", "UTF-32", "a"
p "a".encode("UTF-16").b
