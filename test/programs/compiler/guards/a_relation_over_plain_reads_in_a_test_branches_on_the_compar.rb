# A relation over plain reads as a test: fixnums, flonums, the two
# mixed, a bignum, NaN, nil and a String, in `if`, `unless`, `while`,
# `until`, a ternary and `elsif`; under a refinement; and once
# Integer's and Float's relations are redefined.
def rel(a, b)
  [a < b ? :lt : :no, a <= b ? :le : :no, (:gt if a > b), (:ge unless !(a >= b)), a == b ? :eq : :ne, a != b ? :ne : :eq]
end
p rel(1, 2), rel(2, 2), rel(3, 2), rel(-(2**62), 2**62 - 1)
p rel(1.5, 2), rel(2, 1.5), rel(2.0, 2), rel(0.0, -0.0), rel(2**64, 1), rel(1, 2**64)
nan = Float::NAN
p rel(nan, 1.0), rel(1, nan), rel(nan, nan)
p rel("a", "b"), rel("b", "b")
begin
  1 < nil ? 1 : 2
rescue ArgumentError => e
  p e.message
end
i = 0
n = 5
s = []
while i < n
  s << i
  i += 1
end
until i <= 0
  i -= 2
end
p s, i
x = 7
r = if x < 5 then :small elsif x <= 7 then :seven else :big end
p r
module Backwards
  refine Integer do
    def <(other) = other.to_s < to_s
  end
end
module UseIt
  using Backwards
  def self.lt(a, b) = a < b ? :yes : :no
end
p UseIt.lt(9, 10), UseIt.lt(10, 9), 9 < 10 ? :yes : :no
class Integer
  def <(other) = :redefined
  def ==(other) = false
end
class Float
  def <=(other) = nil
end
p(3 < 2 ? :truthy : :falsy, 2 == 2 ? :eq : :ne, 1.5 <= 2.5 ? :le : :nil)
