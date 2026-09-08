# frozen_string_literal: true

# A `*` splat in the index of `g[...] += v` makes the index count unknown
# at compile time, so both halves of the pair spread ONE saved Array
# rather than a slot array. The index is built once, so a side-effecting
# one runs the number of times it is written.

class Grid
  def initialize = @cells = {}
  def [](*at) = @cells[at]

  def []=(*at, value)
    @cells[at] = value
  end
  def to_s = @cells.inspect
end

g = Grid.new
g[1, 2] = 7
p g[*[1, 2]]

built = 0
coords = lambda do
  built += 1
  [3, 4]
end
g[3, 4] = 0
g[*coords.call] += 10
g[*[3, 4]] += 1
p g[3, 4]
p built

g[*[5, 6]] ||= :fresh
g[*[5, 6]] ||= :later
p g[5, 6]

g[*[7, 8]], g[9] = "x", "y"
p [g[7, 8], g[9]]

h = { [1] => :one }
h[*[[1]]] &&= :changed
p h

# The setter's own answer is not the assignment's: a multiple assignment
# answers the right-hand side.
class Loud
  attr_reader :seen
  def initialize = @seen = []
  def []=(k, v)
    @seen << k
    :ignored
  end
end
loud = Loud.new
p((loud[:a], loud[:b] = 1, 2))
p loud.seen
__END__
7
11
1
:fresh
["x", "y"]
{[1] => :changed}
[1, 2]
[:a, :b]
