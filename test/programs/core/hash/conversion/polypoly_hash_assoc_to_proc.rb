# A Hash with keys and values of any type: Hash#assoc and #rassoc read the
# right entry, and Hash#to_proc looks up the key it gets as an argument.

# a default-proc hash is PolyPoly; assoc/rassoc
h = Hash.new { |hh, k| hh[k] = 42 }
h.merge!(foo: :bar)
p h.assoc(:foo)
p h.assoc(42)
p h.rassoc(:bar)

# heterogeneous-key hash to_proc
g = { 1 => "a", :b => "c", "d" => 2 }
pr = g.to_proc
p pr.call(1)
p pr.call(:b)
p pr.call("d")
p [1, :b, "d"].map(&g)
