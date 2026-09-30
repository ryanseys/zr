# keys / values for sym-keyed hash variants plus str_poly_hash.

# sym_int_hash
h1 = {a: 1, b: 2, c: 3}
puts h1.keys.inspect
puts h1.values.inspect
puts h1.keys.length
puts h1.values.length

# sym_str_hash
h2 = {name: "Alice", role: "admin"}
puts h2.keys.inspect
puts h2.values.inspect

# sym_poly_hash (mixed value types)
h3 = {name: "Alice", age: 30, active: true}
puts h3.keys.inspect
puts h3.values.inspect

# str_poly_hash (string keys, mixed values)
h4 = {"name" => "Alice", "age" => 30, "active" => true}
puts h4.keys.inspect
puts h4.values.inspect

h1.keys.each do |k1|
  puts k1
end
h2.values.each do |sv|
  puts sv
end
h3.keys.each do |k3|
  puts k3
end
h3.values.each do |pv|
  puts pv
end
