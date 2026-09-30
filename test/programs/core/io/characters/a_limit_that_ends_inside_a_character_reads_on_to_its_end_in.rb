# A limit that ends inside a character reads on to its end, in every
# multibyte encoding, not only UTF-8.
def pipe(data, enc = nil)
  r, w = IO.pipe
  r.set_encoding(enc) if enc
  w.write(data.b)
  w.close
  r
end
r = pipe("\xA4\xA2\xA4\xA4\n", "euc-jp")
p [r.gets(1), r.gets(1), r.gets(1)]
r = pipe("\x82\xa0\x82\xa2", "shift_jis")
p [r.gets(1), r.gets(3)]
r = pipe("あい")
p [r.gets(1), r.gets(2), r.gets(4)]
