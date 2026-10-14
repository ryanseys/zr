# Range#step, #each, #cover? and #include? read `<=>` as CRuby's r_less
# does: by its sign (rb_cmpint), so a `<=>` that answers a distance or
# a Float still walks and covers.
class Mark
  include Comparable
  attr_reader :at

  def initialize(at) = @at = at
  def <=>(other) = other.is_a?(Mark) ? at - other.at : nil
  def +(other) = Mark.new(at + other)
  def succ = Mark.new(at + 1)
  def inspect = "M#{at}"
end

class Half
  include Comparable
  attr_reader :at

  def initialize(at) = @at = at
  def <=>(other) = other.is_a?(Half) ? (at - other.at) / 2.0 : nil
  def +(other) = Half.new(at + other)
  def succ = Half.new(at + 1)
  def inspect = "H#{at}"
end

def m(at) = Mark.new(at)
def h(at) = Half.new(at)

p (m(1)..m(4)).step(1).to_a
p (m(1)...m(7)).step(2).to_a
p (m(1)..m(7)).step(3).to_a
p (m(5)..m(1)).step(-1).to_a
p (m(5)...m(1)).step(-2).to_a
p (m(1)..m(1)).step(1).to_a
p (m(1)...m(1)).step(1).to_a
p (h(1)..h(4)).step(1).to_a
p (h(1)...h(4)).step(1).to_a

p (m(1)..m(4)).each.to_a
p (m(1)...m(4)).each.to_a
p (h(1)..h(3)).each.to_a

p (m(1)..m(9)).cover?(m(2)..m(5))
p (m(1)..m(9)).cover?(m(2)..m(10))
p (m(1)...m(9)).cover?(m(2)..m(9))
p (m(1)...m(9)).cover?(m(2)...m(9))
p (m(1)..m(9)).cover?(m(5)..m(2))
p (h(1)..h(3)).cover?(h(2))
p (h(1)...h(3)).cover?(h(3))
p (h(1)..h(3)).cover?(h(1)..h(3))
p (m(1)..m(3)).include?(m(2))
p (m(1)..m(3)) === m(4)
