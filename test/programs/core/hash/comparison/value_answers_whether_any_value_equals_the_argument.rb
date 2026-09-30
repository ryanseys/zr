# Hash#value?(v) and its alias has_value? return true if any value in
# the hash equals v, else false.

# Symbol keys, Integer values
h = { a: 1, b: 2 }
puts h.value?(2)
puts h.value?(99)
puts h.has_value?(1)

# String keys, String values
h2 = { "x" => "alpha", "y" => "beta" }
puts h2.value?("alpha")
puts h2.value?("zzz")

# String keys, Integer values
h3 = { "one" => 1, "two" => 2 }
puts h3.value?(1)
puts h3.value?(3)
