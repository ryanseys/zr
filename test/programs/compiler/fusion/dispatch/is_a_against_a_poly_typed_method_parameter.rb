# A method PARAMETER is always generically typed (zr never infers a
# param's type from its call sites) -- this exercises the runtime
# `is_a?` fallback rather than the static ancestors-constant-fold path.

class Checker
  def check(v)
    v.is_a?(Integer)
  end
end
c = Checker.new
puts c.check(5)
puts c.check("hi")
puts c.check([1, 2])
