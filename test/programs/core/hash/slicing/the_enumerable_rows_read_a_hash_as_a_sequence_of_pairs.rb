# Hash Enumerable conformance
h = { a: 1, b: 2 }
p h.first                                  # first pair
p h.first(1)
p h.take(1)
p h.drop(1)
p({}.first)
p h.sort { |x, y| y[1] <=> x[1] }          # sort with comparator block
p h.sort { |x, y| x[1] <=> y[1] }
p({ "a" => 1, "b" => 2 }.key(2))           # key on a String-keyed hash
p({ 1 => "x", 2 => "y" }.key("y"))
p({ "a" => 1 }.key(9))
p h.any? { |pair| pair[1] > 1 }            # solo param is the pair
p h.count { |pair| pair[1] > 1 }
p h.all? { |pair| pair[1] > 0 }
p h.any? { |k, v| v > 1 }                   # two params still bind k, v
