# Bytes that make no character: case mapping, strip, hex and oct, a
# String pattern, []= and %c each refuse them, or not, as ruby does.
def t(l); p [l, yield]; rescue => e; p [l, e.class, e.message]; end
u = "\xFF"; x = "a\xFFb"
t(:up) { u.upcase }; t(:upx) { x.upcase }; t(:up_ascii) { x.upcase(:ascii) }; t(:cap) { x.capitalize }; t(:down) { "A\xFF".downcase }; t(:swap) { "A\xFF".swapcase }
t(:upbang) { "a\xFF".dup.upcase! }
t(:strip) { " \xFF ".strip }; t(:lstrip) { " \xFF ".lstrip }; t(:rstrip) { " \xFF ".rstrip }; t(:lstrip_ok) { "a\xFF ".lstrip }; t(:rstrip_e) { " \xA1 ".force_encoding("EUC-JP").rstrip }; t(:lstrip_e) { " \xA1 ".force_encoding("EUC-JP").lstrip }
t(:hex) { "\xFF".hex }; t(:oct) { "\xFF".oct }; t(:hex_e) { "\xA1".force_encoding("EUC-JP").hex }; t(:hex_ok) { "0x1f\xA1".force_encoding("EUC-JP").hex }
t(:scan) { "".scan("\xFF") }; t(:scan_e) { "".scan("\xA1".force_encoding("EUC-JP")) }; t(:index) { "abc".index("\xFF") }
t(:binup) { "\xFF".b.upcase }
t(:sjisup) { "\x83".force_encoding("Windows-31J").upcase }
t(:euc_valid) { "\xA1\xA1a".force_encoding("EUC-JP").upcase }
t(:assign) { x = "\xA1\xA1".force_encoding("EUC-JP"); x[-2] = "b".encode("UTF-16LE"); x }
t(:assign2) { x = +"ab"; x[5] = "b".encode("UTF-16LE"); x }
t(:sprintf_c) { format("%c".force_encoding("EUC-JP"), 0xC2) }
t(:sprintf_c2) { format("%c", 0xD800) }
t(:fmt_euc) { format("%c".force_encoding("EUC-JP"), 0xA1A1) }
t(:fmt_sjis) { format("%c".force_encoding("Windows-31J"), 0x81) }
t(:fmt_bin) { format("%c".b, 300) }
t(:sub) { "abc".sub("\xFF", "") }; t(:gsub) { "abc".gsub("\xFF", "") }; t(:match) { "abc".match("\xFF") }; t(:match_p) { "abc".match?("\xFF") }
t(:strip_ok) { "  ab  ".strip }; t(:strip_all) { "    ".strip }; t(:strip_e) { " \xA1\xA1 ".force_encoding("EUC-JP").strip }
t(:hex_sp) { "  \t0x1F".hex }; t(:oct_sp) { " 0b11".oct }
t(:cap_e) { "\xA1".force_encoding("EUC-JP").capitalize }
t(:usascii_up) { "\xFF".force_encoding("US-ASCII").upcase }
