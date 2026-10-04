# `a[i, n] = v` as a target of a multiple assignment writes a slice, not
# one element.
a = [1, 2, 3, 4]
a[0, 2], a[2, 2] = a[2, 2], a[0, 2]
p a
h = {}
begin
  h[1, 2], b = 5, 6
rescue ArgumentError => e
  p e.message
end
class Grid
  def []=(*args)
    p args
  end
end
g = Grid.new
g[1, 2, 3], g[4] = :x, :y
