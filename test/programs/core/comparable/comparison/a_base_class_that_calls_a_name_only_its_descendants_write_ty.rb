# A base-class method calling a name defined ONLY in descendants (here
# Comparable's <=> reading `area`) types as the unify of the descendant
# returns. The call gives the value of the descendant's method, not nil.
class Shape
  include Comparable
  def <=>(other) = area <=> other.area
end
class Rect < Shape
  def initialize(a) = (@a = a)
  def area = @a
end
class Circ < Shape
  def initialize(a) = (@a = a)
  def area = @a * 1.0
end
p(Rect.new(4) > Rect.new(2))
p(Rect.new(3) <=> Circ.new(2))
p(Circ.new(5) < Circ.new(6))
p(Rect.new(2) == Circ.new(2))
