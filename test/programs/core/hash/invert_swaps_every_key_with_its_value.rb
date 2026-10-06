# Hash#invert — swap keys and values.
# String => Integer, String => String, Symbol => Integer and
# Integer => String hashes all invert correctly.

h1 = {"a" => 1, "b" => 2}
p h1.invert

h2 = {a: 1, b: 2}
p h2.invert

h3 = {"a" => "b", "c" => "d"}
p h3.invert

h4 = {1 => "a", 2 => "b"}
p h4.invert
