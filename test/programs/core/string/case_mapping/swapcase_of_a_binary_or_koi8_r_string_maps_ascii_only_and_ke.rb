s = "\xE9a\xC9B".b
p [s.upcase, s.downcase, s.capitalize, s.swapcase, s.swapcase.encoding]
k = "\xE9a\xC9B".b.force_encoding("KOI8-R")
p [k.upcase.b, k.downcase.b, k.swapcase.b, k.swapcase.encoding]
w = "\xE9a\xC9B".b.force_encoding("Windows-1251")
p [w.upcase.b, w.downcase.b, w.swapcase.b]
e = "\xA4\xA2a".b.force_encoding("EUC-JP")
p [e.swapcase.b, e.swapcase.encoding]
b = "\xE9a".b
p [b.swapcase!, b.encoding]
