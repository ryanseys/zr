# A `<=>` with a `return nil` guard can answer an Integer or nil. A second
# class in the program also defines `<=>`, so a call to `<=>` can reach
# either class.
class A
  include Comparable
  attr_reader :v

  def initialize(v)
    @v = v
  end

  def <=>(other)
    return nil unless other.is_a?(A)
    @v <=> other.v
  end
end

# never instantiated: defining it is enough to give `<=>` two owners
class B
  attr_reader :v

  def initialize(v)
    @v = v
  end

  def <=>(other)
    return nil unless other.is_a?(B)
    @v <=> other.v
  end
end

p(A.new(1) <=> A.new(2))
p(A.new(2) <=> A.new(1))
p(A.new(1) <=> A.new(1))

# the guard's own answer
p(A.new(1) <=> 5)
p((A.new(1) <=> 5).nil?)

# Comparable's derived operators over the boxed compare
p(A.new(1) < A.new(2))
p(A.new(2) >= A.new(1))
p [A.new(3), A.new(1), A.new(2)].sort.map(&:v)
p A.new(2).between?(A.new(1), A.new(3))
p A.new(2).clamp(A.new(1), A.new(3)).v

# a mixed-type ivar takes the same route
p(A.new(1) <=> A.new(1))
p(A.new(Rational(1, 2)) <=> A.new(Rational(1, 3)))
