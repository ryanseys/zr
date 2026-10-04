# String: conversions, encodings and argument checks of many methods,
# as CRuby gives them (each line names its case by number).
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
o = Object.new; def o.to_str = "l"
i = Object.new; def i.to_int = 3
show(1) { +"a" << -1 }
show(2) { (+"a").concat(-1) }
show(3) { "hello".byterindex(o) }
show(4) { "hello".byterindex("l", i) }
show(5) { "hello".byterindex(/l/, i) }
show(6) { "hello".byterindex(/l/); $~[0] }
show(7) { "hello".byteslice(nil, 1) }
show(8) { "hello".byteslice(1, nil) }
show(9) { "hello".byteslice(1..2, 1) }
show(10) { s = +"hello"; s.chars { }.equal?(s) }
show(11) { s = +"hello"; s.each_char { }.equal?(s) }
show(12) { s = +"hello"; s.codepoints { }.equal?(s) }
show(13) { s = +"ab"; a = []; [s.grapheme_clusters { |g| a << g }.equal?(s), a] }
x = Object.new; def x.to_str; puts "to_str"; "h"; end
show(14) { (+"hello").delete_prefix!(x) }
show(15) { (+"hello").delete_suffix!(x) }
show(16) { "hello".gsub(/l/, Object.new) }
show(17) { "hello".sub(Object.new, "x") }
show(18) { "hello".sub(/l/, Object.new) }
show(19) { "hello".match(o) }
show(20) { "a".encode("US-ASCII").succ.encoding }
show(21) { "a".encode("US-ASCII").next.encoding }
show(22) { "\xff".force_encoding("US-ASCII").ord }
show(23) { "hello".scan(o) }
show(24) { "hello".rindex(o) }
show(25) { "hello".rindex("l", i) }
show(26) { "hello".rindex(/l/, i) }
show(27) { (+"hello").slice!(i) }
show(28) { (+"hello").slice!(i, i) }
r = Object.new; def r.to_int = 1
show(29) { (+"hello").slice!(r..r) rescue $! }
show(30) { "a,b".split(",", 2**31) }
show(31) { "a".encode("UTF-16LE").to_c }
show(32) { "1".encode("UTF-16LE").to_f }
show(33) { "YWJj\nREVG\n".unpack("u") }
show(34) { "#86)C\n#1$5&\n".unpack("u") }
show(35) { "#86)C\n#1$5&\n".unpack("u*") }
show(36) { (+"\xFFa").force_encoding("UTF-8").lstrip! }
show(37) { (+" \xFFa").force_encoding("UTF-8").lstrip! }
show(38) { "hello".end_with?("o".encode("UTF-16BE")) }
show(39) { "a".encode("EUC-JP").upto("b".encode("ISO-2022-JP")).to_a }
show(40) { "hello".slice!(/(.)(.)/, -1) rescue $! }
show(41) { s = +"hello"; s.sub(/l/) { s << "x"; "y" } }
show(42) { s = +"hello"; s.sub!(/l/) { s << "x"; "y" } }
show(43) { m = Object.new; def m.match(*) = :foo; "h".match(Regexp.new("h")) }
