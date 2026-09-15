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

__END__
"a\u00E9\u65E5\u{1F600}"
4
97
128512
[97, 233, 26085, 128512]
12
"A\xC3\x89\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
"A\xC3\x89\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
"A\xC3\xA9\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
"\xED\xA0\xBD\xED\xB8\x80\xE6\x97\xA5\xC3\xA9a"
"\"a\\xC3\\xA9\\xE6\\x97\\xA5\\xED\\xA0\\xBD\\xED\\xB8\\x80\""
"\xC3\xA9"
"\xED\xA0\xBD\xED\xB8\x80"
#<RangeError: invalid codepoint 0xD800 in CESU-8>
#<RangeError: 1114112 out of char range>
"x\xED\xA0\xBD\xED\xB8\x81"
4
"**a\xC3\xA9\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80***"
"\"a\\u00E9\\u65E5\\u{1F600}\""
"\"\\u{1F600}\""
false
"\"\\xED\\xA0\\x80\""
#<ArgumentError: invalid byte sequence in CESU-8>
#<RangeError: invalid codepoint 0xD800 in UTF8-MAC>
#<ArgumentError: invalid byte sequence in UTF8-MAC>
#<RangeError: invalid codepoint 0xD800 in UTF8-MAC>
"\"a\\xC3\\xA9\""
"\"\\xC6\\xFC\""
"\"\\u00E9\""
