# Hash#merge of two hashes with the same key type but different value
# types. The result holds the values of both types.

# Sym + Sym with mixed value types.
h1 = { a: 1, b: 2 }
h2 = { c: "x", d: "y" }
h3 = h1.merge(h2)
puts h3[:a].inspect
puts h3[:c].inspect

# Str + Str with mixed value types.
s1 = { "a" => 1, "b" => 2 }
s2 = { "c" => "x", "d" => "y" }
s3 = s1.merge(s2)
puts s3["a"].inspect
puts s3["c"].inspect

puts "ok"
