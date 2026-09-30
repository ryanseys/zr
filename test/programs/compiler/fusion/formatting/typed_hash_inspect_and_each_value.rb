# inspect for a hash with Symbol keys and Integer values, plus
# Hash#each_value across common kinds of hash.
h = {a: 1, b: 2}
puts h.inspect
h.each_value { |v| puts v * 10 }

# String keys, Integer values.
counts = {"x" => 5, "y" => 7}
counts.each_value { |v| puts v + 1 }

# inspect on String keys, Integer values.
puts counts.inspect
