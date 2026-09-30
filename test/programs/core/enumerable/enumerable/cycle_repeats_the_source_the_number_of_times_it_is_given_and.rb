# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- cycle -----------------------------------------------------------------
p [1, 2, 3].cycle(2).to_a
p [1, 2].cycle(0).to_a
seen = []
[1, 2].cycle(2) { |x| seen << x }
p seen

# With no count `cycle` repeats forever, so it only ends via `break`.
count = 0
[1, 2].cycle do |x|
  count += 1
  break if count == 5
end
p count

