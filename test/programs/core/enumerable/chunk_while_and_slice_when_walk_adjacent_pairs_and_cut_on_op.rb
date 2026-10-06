# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- chunk_while / slice_when ----------------------------------------------
# Exact negations of each other: both walk adjacent pairs and cut between
# them, `chunk_while` when the block is false, `slice_when` when it's true.
runs = [1, 2, 4, 9, 10, 11, 12, 15]
p runs.chunk_while { |i, j| i + 1 == j }.to_a
p runs.slice_when { |i, j| i + 1 != j }.to_a
p [1, 1, 2, 3, 3].chunk_while { |i, j| i == j }.to_a

# No adjacent pair means the block never runs.
p [].chunk_while { |i, j| true }.to_a
p [7].chunk_while { |i, j| true }.to_a

