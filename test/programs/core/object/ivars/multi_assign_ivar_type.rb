# `@a, @b = x, y` must propagate the param types into the ivars just
# like separate `@a = x; @b = y` assignments do, so a chained <=> on
# the attr_reader values dispatches correctly.
class V
  include Comparable
  attr_reader :maj, :min
  def initialize(maj, min); @maj, @min = maj, min; end
  def <=>(other)
    cmp = @maj <=> other.maj
    if cmp == 0
      cmp = @min <=> other.min
    end
    cmp
  end
end
a = V.new(1, 2)
b = V.new(1, 10)
puts "a<b=#{a < b}"
puts "b<a=#{b < a}"
puts "eq=#{V.new(3, 4) == V.new(3, 4)}"
