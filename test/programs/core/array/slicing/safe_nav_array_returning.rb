# `x&.keys` / `&.values` / `&.to_a` on a receiver that is not statically a
# Hash: the result is nil for a nil receiver, and an Array for a Hash.
x = nil
p(x&.keys)
p(x&.values)
p(x&.to_a)
rows = [{ "a" => 1 }]
p(rows.first&.keys)
p(rows.first&.values)
p(rows.first&.to_a)
h = { "a" => 1 }
p(h&.keys)
p(rows.first&.size)
r2 = [["x", "y"]]
p(r2.first&.reverse)
empty = []
p(empty.first&.keys)
