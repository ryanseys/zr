s = "\xF9\x41".b.force_encoding("SJIS-SoftBank")
r = s.encode("UTF8-SoftBank")
p [r.b, r.encoding]
p s.encode("UTF8-SoftBank").encode("SJIS-SoftBank").b
