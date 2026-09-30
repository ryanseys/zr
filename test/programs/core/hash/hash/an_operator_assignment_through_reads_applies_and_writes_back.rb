# Hash#[] op= for string-valued and poly-valued typed hashes.

# Symbol => String: += str → concat.
h = {a: "hello", b: "world"}
h[:a] += "!"
puts h[:a]

# String => String: += str → concat.
h2 = {"a" => "hello", "b" => "world"}
h2["a"] += "!"
puts h2["a"]

# Symbol => mixed: += int on a hash whose values are mixed.
h3 = {a: 1, b: 2.0}
h3[:a] += 10
puts h3[:a]

# String => mixed: += int.
h4 = {"a" => 1, "b" => 2.0}
h4["a"] += 10
puts h4["a"]
