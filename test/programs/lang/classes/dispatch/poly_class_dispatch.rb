# `.class` on a value of unknown type gives its runtime class, for
# each element of a heterogeneous array.
a = [1, "hello", 2.0, :sym, nil, true, false]
puts a[0].class
puts a[1].class
puts a[2].class
puts a[3].class
puts a[4].class
puts a[5].class
puts a[6].class
