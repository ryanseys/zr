# `obj == 2**64` calls the object's own `==`, and `obj < 2**64` calls its own
# `<`. A big Integer operand does not change which method runs.
class Exp
  def initialize(v) = @v = v
  def ==(other)
    @v == other ? "eq" : "ne"
  end
  def <(other) = "lt-called"
end

def wrap(v) = Exp.new(v)
p(wrap(2**64) == 18446744073709551616)
p(wrap(1) == 18446744073709551616)
p(wrap(1) < 18446744073709551616)

# the numeric comparisons themselves are unchanged
p(2**64 == 18446744073709551616)
p(2**64 == 5)
p(5 == 2**64)
p((2**64) > 5)
p(5 < 2**64)
p((2**64) <=> 5)
