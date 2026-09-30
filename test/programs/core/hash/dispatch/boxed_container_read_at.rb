# Array#at is Array#[] for one integer, and a container read out of a hash
# value must reach it. A nested hash with Integer keys reads the same way.
h = { "a" => [7, 8, 9] }
p h["a"].at(0)
p h["a"].at(-1)
p h["a"][1]
p [1, 2, 3].at(1)
xs = [4, 5]
p xs.at(0)

q = { "a" => { 1 => "x", 2 => "y" } }
p q["a"][1]
p q["a"][9]
r = { "a" => { 1 => 10 } }
p r["a"][1]
s = { "a" => { :k => "v" } }
p s["a"][:k]
