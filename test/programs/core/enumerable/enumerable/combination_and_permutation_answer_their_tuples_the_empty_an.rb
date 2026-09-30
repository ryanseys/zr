# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- Array combinatorics ---------------------------------------------------
p [1, 2, 3].combination(2).to_a
p [1, 2, 3].combination(0).to_a   # one EMPTY tuple...
p [1, 2, 3].combination(4).to_a   # ...but none at all past the length
p [1, 2, 3].permutation(2).to_a
p [1, 2].permutation.to_a         # no argument = full length

# The block form yields each tuple.
picked = []
[1, 2, 3].combination(2) { |c| picked << c.sum }
p picked

