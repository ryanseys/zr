# A Hash literal whose only values are empty array literals (with no known
# element type) is still a normal Hash that takes writes.
p({ "empty" => [] })
h = { "a" => [1], "empty" => [] }
p h
p({ 1 => [] })
g = { "x" => [], "y" => [] }
g["x"] << 5
p g
