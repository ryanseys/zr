# The wasm32 module of this program runs past 2 GB.
s = "héllo wörld"
p s, s.size, s.length, s.bytesize, s[1], s[-1], s[1, 3], s[1..3], s[1...-1], s[7..], s[..1], s[20], s[11], s[11, 2], s[12, 2], s["llo"], s["ö"], s["x"], s[-3, 2]
p s.chars, s.chars.size, s.each_char.to_a.last(3), s.bytes.size, s.codepoints, s.reverse, s.reverse.size, s.index("l"), s.index("ö"), s.index("w", 3), s.rindex("l"), s.rindex("ö"), s.index("x"), s.include?("ö"), s.start_with?("hé"), s.end_with?("rld")
p s.center(15, "*"), s.ljust(13, "é"), s.rjust(14), s.center(3), "é".center(4, "ab"), s.chop, s.chop.size, s.chr, "".chr, s.ord, "é".ord, "€".ord, "😀".ord, "😀".size, "😀".bytesize, "😀".bytes, "😀"[0], "a😀b"[1], "a😀b"[2], "a😀b".reverse
t = +"añb"
t.insert(1, "X")
t.insert(-1, "Y")
t.insert(-3, "Z")
p t, t.size
u = +"añb"
u[1] = "ÑÑ"
p u, u.size
u[0, 2] = "q"
p u
u[1..] = "😀"
p u, u.size
v = +"añbñc"
p v.slice!(1), v, v.slice!(1, 2), v, v.slice!("c"), v, v.slice!(5), v
p "añb".split(""), "a ñ b".split, "a,ñ,b".split(","), "añb".each_char.map(&:ord), "añb".scan("ñ"), "añb".partition("ñ"), "añb".rpartition("ñ"), "añb".sub("ñ", "n"), "añb".gsub("ñ", "nn")
p "añb".strip, "  añb\n".strip, "añb\n".chomp, "añb" * 2, "añb" + "ç", "añb" <=> "añc", "añb" == "añb", "añb".eql?("añb"), "añb".hash == "añb".hash, "añb".to_sym, :añb.to_s, "añb".to_sym.size, "añb".freeze.frozen?, "añb".dup, "añb".b, "añb".b.size, "añb".b.inspect, "añb".inspect, "é".inspect, "a b".inspect, "\x7f".inspect, "a\xffb".inspect, "a\xffb".valid_encoding?, "añb".valid_encoding?, "añb".ascii_only?, "abc".ascii_only?, "a\xffb".size, "a\xffb".chars, "\x01\x00".inspect, "a\xffb".b.inspect
p("\xff".ord) rescue p $!
p "añb".encoding, "añb".b.encoding, "abc".encoding, "añb".encoding.name, "añb".encoding.to_s, "añb".encoding.inspect, Encoding::UTF_8 == "a".encoding, Encoding::BINARY, Encoding::ASCII_8BIT.equal?(Encoding::BINARY), Encoding::UTF_8.names.first, Encoding::US_ASCII, "a".force_encoding("BINARY").encoding, "a".force_encoding(Encoding::UTF_8).encoding, "añb".force_encoding("ASCII-8BIT").size, "añb".b.force_encoding("UTF-8").size, "añb".encode("UTF-8"), Encoding.default_external, Encoding.default_internal
p "añb".dump, "😀".dump, "a\xffb".dump
p "%s|%5s|%-5s|" % ["ñ", "ñ", "ñ"], "ñ".ljust(3).size, "añb".sum, "añb".hex, "añb".to_i, "ñ1".to_i, "1ñ".to_i
w = +""
w << "ñ" << 241 << 0x1F600
p w, w.size, w.bytesize, w.codepoints, 65.chr, 200.chr.encoding, 200.chr.bytes, 241.chr(Encoding::UTF_8), 0x1F600.chr("UTF-8")
p "añb".each_char.with_index.to_a, "añb".each_char.select { |c| c.ord > 127 }, "añb".bytes.map { |b| b.to_s(16) }, "añb".getbyte(1), "añb".byteslice(1, 2), "añb".byteslice(1, 1).valid_encoding?, "añb".byteslice(1, 1).inspect, "añb".byteslice(1, 1).size
h = { "ñ" => 1, ñ: 2 }
p h, h["ñ"], h[:ñ], h.keys.map(&:size)
def ünïcode(ñ) = ñ * 2
p ünïcode(3), method(:ünïcode).name, "añb".respond_to?(:size), "añb".ljust(1), "añb".delete_prefix("a"), "añb".delete_suffix("ñb"), "añb".start_with?("añ"), "añbañb".index("ñ", 2), "añbañb".rindex("ñ", 3), "añb".insert(3, "!"), "añb".index(""), "añb".index("", 3), "añb".index("", 4)
GC.start
p ["ñ" * 100].map { |x| x.size }, ("ñ" * 100).reverse[0, 3], ("añ" * 50).chars.uniq, "añb".sum(8)
