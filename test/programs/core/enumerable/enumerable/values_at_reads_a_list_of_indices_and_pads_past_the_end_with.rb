# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- values_at / each_index ------------------------------------------------
p [1, 2, 3].values_at(0, 2, 5)     # out of bounds is nil, not skipped
p [1, 2, 3].values_at(-1, -3)
p [1, 2, 3].values_at(0..1)
p [1, 2, 3, 4, 5].values_at(3..9)  # one entry PER INDEX the range names
p [1, 2, 3].each_index.to_a

