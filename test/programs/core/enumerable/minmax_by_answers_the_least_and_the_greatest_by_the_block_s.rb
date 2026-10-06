# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- minmax_by -------------------------------------------------------------
p [1, 2, 3, 4].minmax_by { |x| -x }
p ["a", "bbb", "cc"].minmax_by { |s| s.length }
p [].minmax_by { |x| x }          # a nil PAIR, not []

