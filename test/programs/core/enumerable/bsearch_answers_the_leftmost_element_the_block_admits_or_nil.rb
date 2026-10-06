# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- bsearch ---------------------------------------------------------------
# Find-minimum mode: the array is sorted so every false precedes every true,
# and the answer is the first true.
sorted = [1, 2, 3, 4, 5]
p sorted.bsearch { |x| x >= 3 }
p sorted.bsearch { |x| x >= 99 }  # nil when nothing matches
p sorted.bsearch_index { |x| x >= 3 }

