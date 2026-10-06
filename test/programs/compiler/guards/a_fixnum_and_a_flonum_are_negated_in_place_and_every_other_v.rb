# `-x` on a fixnum and on a flonum in place: the fixnum ends, the zeros,
# the flonum whose negation is no flonum, a heap Float, NaN and the
# infinities, a Rational, and both methods once redefined.
def neg(x) = -x
min = -(2**62)
p neg(5), neg(-5), neg(0), neg(min), neg(min).class, neg(2**62 - 1), neg(2**64)
p neg(1.5), neg(-2.25), neg(0.0), neg(-0.0), 1 / neg(0.0), 1 / neg(-0.0)
hole = [0xB000000000000000].pack("Q<").unpack1("E")
p neg(hole), neg(neg(hole)), neg(hole) == -hole, neg(1e300), neg(-1e-300)
p neg(Float::INFINITY), neg(-Float::INFINITY), neg(Float::NAN).nan?, neg(3r / 4)
x = 0.0
i = 0
while i < 1000
  x = -x + 1.0
  i += 1
end
p x
class Float
  def -@ = :float_neg
end
p neg(1.5), neg(0.0), neg(2)
class Integer
  def -@ = :int_neg
end
p neg(2), neg(1.5)
