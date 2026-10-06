# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- the destructive forms -------------------------------------------------
# `flatten!` answers nil when nothing changed; `sort_by!` always answers the
# receiver.
p [[1, [2, 3]], [4]].flatten!
p [1, 2].flatten!
nested = [1, [2, [3, [4]]]]
p nested.flatten!(1)
ordered = [3, 1, 2]
ordered.sort_by! { |x| -x }
p ordered

