# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- Array.new -------------------------------------------------------------
p Array.new
p Array.new(3)
p Array.new(3) { |i| i * i }

# The default-value form SHARES one object across every slot -- which is
# exactly why the block form exists.
shared = Array.new(2, "x")
p shared
shared[0] << "!"
p shared

fresh = Array.new(2) { "x" }
fresh[0] << "!"
p fresh

