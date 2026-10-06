# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- grep / grep_v ---------------------------------------------------------
# Also `===`, so a Range covers, a Class checks is_a?, a Regexp matches.
p (1..10).grep(3..5)
p [1, "a", 2, "b"].grep(Integer)
p ["apple", "banana", "cherry"].grep(/an/)
p [1, "a", 2, "b"].grep_v(Integer)

# A block maps the survivors.
p [1, "a", 2, "b"].grep(Integer) { |x| x * 10 }
p [1, "a", 2, "b"].grep_v(Integer) { |x| x.upcase }

