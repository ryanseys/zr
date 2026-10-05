# A range that holds itself compares equal to another such range, and
# shows itself as (... .. ...) inside its own inspect, as ruby's
# recursion guards make it.
class CyclicRange < Range
  def <=>(_other) = true
end

x = CyclicRange.allocate
x.send(:initialize, x, 1)
y = CyclicRange.allocate
y.send(:initialize, y, 1)
z = CyclicRange.allocate
z.send(:initialize, z, :another)
p [x == y, x.eql?(y), x == z, x.eql?(z)]
p x.inspect

w = CyclicRange.allocate
w.send(:initialize, w, 2, true)
p w.inspect
p [(1..2) == (1..2), (1..2).eql?(1.0..2), (1..2) == (1...2)]
