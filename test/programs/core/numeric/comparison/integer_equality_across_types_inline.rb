class Eq
  def ==(other) = other == 1
end

def cmp(a, b) = [a == b, a != b]

p cmp(1, 1.0), cmp(1, 1.5), cmp(1, 1r), cmp(1, Eq.new)
p cmp(1, 2), cmp(1, 1), cmp(1, nil), cmp(1, "1")
p cmp(2**64, 2**64), cmp(1, 2**64)
p cmp(-3, -3.0), cmp(0, -0.0)

