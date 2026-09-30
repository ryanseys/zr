# An absent Object method on a blank-slate receiver raises INSIDE the
# enclosing handler's region, so the rescue modifier catches it.
class BO < BasicObject
  def initialize; @x = 1; end
  def own; @x; end
end
a = BO.new
r = (a.dup.own rescue $!.class)
p r
p a.own
