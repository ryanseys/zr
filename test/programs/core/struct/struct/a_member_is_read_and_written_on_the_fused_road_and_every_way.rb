# A member read and written on the fused road, and every way off it: a
# struct with no values yet, a frozen one, a subclass with an ivar
# before the values, and a member the class no longer has.
P = Struct.new(:x, :y)
pt = P.new(1, 2)
i = 0
while i < 3
  pt.x = pt.x + pt.y
  i += 1
end
p pt.x, pt.y, pt
bare = P.allocate
p bare.x
bare.y = 5
p bare, bare.x
class Q < P
  def initialize(*)
    @first = :ivar
    super
  end
end
q = Q.new(7, 8)
q.x = q.y * 2
p q, q.instance_variable_get(:@first)
f = P.new(1, 2).freeze
p f.x
begin
  f.x = 9
rescue FrozenError => e
  p e.class
end
