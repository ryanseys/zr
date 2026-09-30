# Enumerable chunking/slicing and Array combinatorics/search.
#
# Everything here is driven by the receiver's own `each`, so it works the
# same on an Array, a Range, or a user class that includes Enumerable --
# which the last section shows.

# --- all of it works on a user Enumerable ----------------------------------
class Steps
  include Enumerable

  def initialize(*values)
    @values = values
  end

  def each(&blk)
    @values.each(&blk)
    self
  end
end

steps = Steps.new(1, 2, 4, 5, 6, 9)
p steps.chunk_while { |i, j| i + 1 == j }.to_a
p steps.grep(2..5)
p steps.minmax_by { |x| -x }
p steps.slice_before(&:even?).to_a
