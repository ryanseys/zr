# CESU-8 holds Unicode's code points: three bytes as UTF-8 writes them,
# or six for a character past the BMP, a pair of surrogates.
c = "aé日\u{1F600}".encode("CESU-8")
p c, c.length, c.ord, c[3].ord, c.codepoints, c.bytes.size
p c.upcase.b, c.swapcase.b, c.capitalize.b, c.reverse.b, c.dump
p 0xE9.chr("CESU-8").b, 0x1F600.chr("CESU-8").b, (0xD800.chr("CESU-8").b rescue $!), (0x110000.chr("CESU-8") rescue $!)
s = +"x".encode("CESU-8"); s << 0x1F601; p s.b
p c.each_grapheme_cluster.count, c.center(9, "*").b, c.inspect, c[3].inspect
p "\xED\xA0\x80".b.force_encoding("CESU-8").valid_encoding?, "\xED\xA0\x80".b.force_encoding("CESU-8").inspect
p (("\xFF".b.force_encoding("CESU-8")).ord rescue $!)
m = "aé".b.force_encoding("UTF8-MAC")
p (0xD800.chr("UTF8-MAC") rescue $!), ("\xFF".b.force_encoding("UTF8-MAC").ord rescue $!), (m << 0xD800 rescue $!)
p m.dump, "日".encode("EUC-JP").dump, "é".dump

