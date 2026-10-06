# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- zip -------------------------------------------------------------------
p [1, 2, 3].zip([4, 5, 6])
p [1, 2, 3].zip([4, 5], [6])      # short others pad with nil
p [1, 2].zip([3, 4], [5, 6])
p([1, 2].zip([3, 4]) { |pair| })  # the block form answers nil

