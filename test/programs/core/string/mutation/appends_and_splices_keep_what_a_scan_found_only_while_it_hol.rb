# `<<` and `bytesplice` keep a String's known-ASCII state across a change
# of plain ASCII, and lose it for a byte past ASCII: ascii_only?, index
# and the encoding answer from the bytes as they are after each change.
def show(label)
  v = yield
  v = [v, v.encoding, v.ascii_only?, v.valid_encoding?] if v.is_a?(String)
  puts "#{label}: #{v.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

s = +"abc".b
s.ascii_only?
show("binary << binary past ASCII") { s << "\xFF".b }
t = +"abc".b
t.ascii_only?
show("binary << UTF-8 ASCII") { t << "de" }
show("then << UTF-8 past ASCII") { t << "é" }
u = +"abc"
u.ascii_only?
show("UTF-8 << é") { u << "é" }
show("index after it") { u.index("é") }
v = +"héllo"
show("index from a character") { v.index("l", 3) }
show("rindex") { v.rindex("l") }
w = +"abc".b
w.ascii_only?
w << "x".b
w << "\x80".b
show("two appends") { [w.ascii_only?, w.index("\x80".b)] }
long = +""
2000.times { |i| long << "n#{i}".b << "\0" }
show("a long join") { [long.bytesize, long.encoding, long.ascii_only?, long.index("n1999"), long.count("\0")] }

show("splice itself at the head") { x = +"abcdef"; x.bytesplice(0, 1, x) }
show("splice itself in the middle") { x = +"abcdef"; x.bytesplice(2, 3, x) }
show("splice a range") { x = +"hello"; x.bytesplice(1..2, "EE") }
show("splice past ASCII into ASCII") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é") }
show("index after that splice") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é"); x.index("l") }
show("splice binary into UTF-8") { x = +"hello"; x.bytesplice(1, 1, "\xFF".b) }
show("splice UTF-8 into binary past ASCII") { x = +"h\xFFllo".b; x.bytesplice(0, 1, "é") }
show("splice binary ASCII into UTF-8") { x = +"héllo"; x.bytesplice(0, 1, "Z".b) }
show("splice inside a character") { x = +"héllo"; x.bytesplice(2, 1, "Z") }
show("splice a frozen String") { "abc".freeze.bytesplice(0, 1, "Z") }
show("splice part of the text") { x = +"hello"; x.bytesplice(0, 1, "WXYZ", 1, 2) }
show("splice that grows") { x = +"ab"; x.bytesplice(1, 0, "0123456789" * 20); [x.bytesize, x.ascii_only?] }
show("many splices then index") { x = +("abcdefgh" * 50); x.ascii_only?; 50.times { |i| x.bytesplice(i * 8, 1, "Z") }; [x.index("Zb", 390), x.count("Z")] }

