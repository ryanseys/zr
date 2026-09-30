# Array#compact! on a mixed array removes the nils in place, and
# returns the receiver. (It returns nil when nothing was removed,
# and this example does not test that case.)
a = [1, nil, 2, nil, 3]
a.compact!
puts a.inspect

# Mixed types with nils interleaved
b = ["a", nil, :sym, nil, 42]
b.compact!
puts b.inspect

# Already nil-free
c = [1, "two", :three]
c.compact!
puts c.inspect
