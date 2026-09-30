# Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
# `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
# Each is duck-typed -- any object answering the method participates.

# --- to_ary ----------------------------------------------------------------

class Pair
  def initialize(a, b)
    @a = a
    @b = b
  end
  def to_ary = [@a, @b]
end

# Block auto-splat coerces through to_ary.
def one(v)
  yield v
end
p(one(Pair.new(1, 2)) { |a, b| [a, b] })

# Multiple assignment destructures through to_ary.
x, y = Pair.new(3, 4)
p [x, y]

# An Array splice coerces the right-hand side through to_ary.
arr = [1, 2, 3]
arr[1, 1] = Pair.new(7, 8)
p arr

# A `for` loop's destructuring target.
[[1, 2]].each do |a, b|
  p [a, b]
end
