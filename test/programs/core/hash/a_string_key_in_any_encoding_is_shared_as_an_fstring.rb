# -*- coding: us-ascii -*-
# A Hash keeps a bare String key as the one frozen String of its bytes
# and its encoding, in US-ASCII as in UTF-8, and Strings of different
# encodings stay apart (test_hash.rb's fstring key tests).
a, b = {}, {}
a["abc"] = 1
b["abc"] = 1
p a.keys[0].equal?(b.keys[0]), a.keys[0].frozen?
x = {"ABC" => :t}
y = {"ABC" => :t}
p x.keys[0].equal?(y.keys[0]), x.keys[0].equal?("ABC".freeze)
u = "_"
c, d = {}, {}
c["abc#{u}def"] = 1
d["abc#{u}def"] = 1
p c.keys[0].equal?(d.keys[0])
p "abc".b.then { |s| -s }.encoding, (-"abc".b).equal?(-"abc".dup.force_encoding("BINARY")), (-"abc").equal?(-"abc".b)
p (-"x").encoding, (-"x".encode("UTF-8")).encoding
