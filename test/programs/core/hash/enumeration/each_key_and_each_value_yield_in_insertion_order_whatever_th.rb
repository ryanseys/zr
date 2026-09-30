# Hash#each_key / #each_value with a block across many kinds of keys
# and values. Keys and values are yielded in insertion order. Mixed
# or object values are printed via to_s so array values render on a
# single line.

# Symbol keys, Integer values
h_sym_int = { a: 1, b: 2, c: 3 }
h_sym_int.each_key { |k| puts k }
puts "-"
h_sym_int.each_value { |v| puts v }
puts "=="

# Symbol keys, String values
h_sym_str = { x: "one", y: "two" }
h_sym_str.each_key { |k| puts k }
puts "-"
h_sym_str.each_value { |v| puts v }
puts "=="

# Symbol keys, mixed scalar values
h_sym_poly = { a: 1, b: "two" }
h_sym_poly.each_key { |k| puts k }
puts "-"
h_sym_poly.each_value { |v| puts v.to_s }
puts "=="

# Symbol keys, object values
h_sym_poly_obj = { a: [1], b: [2, 3] }
h_sym_poly_obj.each_key { |k| puts k }
puts "-"
h_sym_poly_obj.each_value { |v| puts v.to_s }
puts "=="

# String keys, Integer values
h_str_int = { "a" => 1, "b" => 2 }
h_str_int.each_key { |k| puts k }
puts "-"
h_str_int.each_value { |v| puts v }
puts "=="

# String keys, String values
h_str_str = { "a" => "x", "b" => "y" }
h_str_str.each_key { |k| puts k }
puts "-"
h_str_str.each_value { |v| puts v }
puts "=="

# String keys, mixed scalar values
h_str_poly = { "a" => 1, "b" => "two" }
h_str_poly.each_key { |k| puts k }
puts "-"
h_str_poly.each_value { |v| puts v.to_s }
puts "=="

# String keys, object values
h_str_poly_obj = { "a" => [1], "b" => [2, 3] }
h_str_poly_obj.each_key { |k| puts k }
puts "-"
h_str_poly_obj.each_value { |v| puts v.to_s }
puts "=="

# Integer keys, String values
h_int_str = { 1 => "one", 2 => "two" }
h_int_str.each_key { |k| puts k }
puts "-"
h_int_str.each_value { |v| puts v }
puts "=="

# Integer keys, Integer values
h_int_int = { 1 => 10, 2 => 20 }
h_int_int.each_key { |k| puts k }
puts "-"
h_int_int.each_value { |v| puts v }
puts "=="

# Object keys and values of mixed types
h_poly_poly = {}
h_poly_poly[[1, 2]] = "ab"
h_poly_poly[[3, 4]] = "cd"
h_poly_poly["s"] = 99
h_poly_poly[5] = [10, 20]
h_poly_poly.each_key { |k| puts k.to_s }
puts "-"
h_poly_poly.each_value { |v| puts v.to_s }
puts "=="
