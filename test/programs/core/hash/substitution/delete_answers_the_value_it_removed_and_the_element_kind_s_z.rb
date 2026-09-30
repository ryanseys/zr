h_si = { a: 1, b: 2, c: 3 }
v1 = h_si.delete(:a)
puts v1
puts h_si.size

h_ss = { x: "one", y: "two" }
v2 = h_ss.delete(:x)
puts v2
puts h_ss.size

# delete of a missing key returns nil, as in CRuby
h2 = { a: 1 }
puts h2.delete(:b)
puts h2.size

# Symbol keys, values of mixed types
h_sp = { a: 1, b: "two", c: :sym }
v3 = h_sp.delete(:b)
puts v3.inspect
puts h_sp.size
