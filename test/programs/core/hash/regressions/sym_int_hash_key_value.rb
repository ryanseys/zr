# Hash#key(value) / #value? / #has_value? on a hash with Symbol keys.
h = {a: 1, b: 2, c: 3}
puts h.key(2).inspect
puts h.has_value?(2)
puts h.has_value?(99)
puts h.value?(3)
