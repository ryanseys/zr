# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- slice_before / slice_after --------------------------------------------
# `before` puts the match at the START of the next slice, `after` at the END
# of the current one.
p [1, 2, 3, 4, 5].slice_before { |x| x.even? }.to_a
p [1, 2, 3, 4, 5].slice_after { |x| x.even? }.to_a

# A match at the very start opens the first slice -- it does not close an
# empty one.
p [1, 2, 3].slice_before { |x| x == 1 }.to_a

# Both also take a PATTERN instead of a block, matched with `===`.
p [1, 2, 3, 4, 5].slice_before(3).to_a
p [1, 2, 3, 4, 5].slice_after(3).to_a
p ["a", "b1", "c"].slice_before(/\d/).to_a

