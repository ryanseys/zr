# Hash#transform_values for different key and value types. The block
# runs once per value, its return becomes the new value, and the keys
# and order stay the same.

# === Symbol keys, Integer values ===
# `{a: 1, b: 2}` has Symbol keys and Integer values. transform_values
# keeps the key set and feeds each value through the block. p prints
# the result in Ruby's `{a: V, b: V, ...}` form.
p({a: 1, b: 2}.transform_values { |v| v * 10 })
p({x: 5, y: 10, z: 15}.transform_values { |v| v + 100 })
puts({a: 1, b: 2, c: 3}.transform_values { |v| v * v }[:c])
puts({foo: 7}.transform_values { |v| v - 2 }[:foo])

# Non-destructive — original hash retains its values; result is a
# fresh hash. transform_values must not mutate the receiver.
hh = {a: 1, b: 2}
hh2 = hh.transform_values { |v| v * 100 }
p hh         # {a: 1, b: 2}
p hh2        # {a: 100, b: 200}

# === Integer keys, String values ===

# Identity transform — values unchanged
h1 = {1 => "alpha", 2 => "beta"}
puts h1.transform_values { |v| v }[1]
puts h1.transform_values { |v| v }[2]

# Upcase values
h2 = {1 => "hello", 2 => "world"}
upper = h2.transform_values { |v| v.upcase }
puts upper[1]
puts upper[2]

# String concat
h3 = {1 => "a", 2 => "b", 3 => "c"}
suff = h3.transform_values { |v| v + "!" }
puts suff[1]
puts suff[2]
puts suff[3]

# Length preserved across transform
big = {10 => "one", 20 => "two", 30 => "three"}
puts big.transform_values { |v| v + "?" }.length

# Empty block maps every value to nil (CRuby parity), also when
# the values were Strings.
empty = {1 => "alpha", 2 => "beta"}.transform_values { }
puts empty[1].nil?
puts empty[2].nil?
puts empty.length
