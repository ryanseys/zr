p({ a: 1, b: 2 }.transform_keys(a: :x))
p({ a: 1, b: 2 }.transform_keys(a: :x) { |k| k.to_s })
h = { a: 1, b: 2 }
h.transform_keys!(b: :y)
p h
