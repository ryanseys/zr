# Proc#curry and Method#curry read the arity as a C int (NUM2INT): a
# Float or Rational truncates, to_int converts, and a value past the
# int range raises RangeError.
l = ->(*a) { a }
pr = proc { |a, b, c| [a, b, c] }
two = ->(a, b) { [a, b] }
o = Object.new
def o.to_int = 2
[2**40, -2**40, 2**64, 2.9, 1r, o, "1", nil, -1, 2**31 - 1, 2**31].each do |arity|
  c = l.curry(arity)
  p [arity.is_a?(Object) && !arity.is_a?(Numeric) && !arity.nil? && !arity.is_a?(String) ? :to_int : arity, c.arity, c.lambda?]
rescue => e
  p [e.class, e.message.sub(/0x\h+/, "XX")]
end
[2.9, 1r, o].each do |arity|
  p two.curry(arity)[1][2] rescue p [$!.class, $!.message]
end
p pr.curry(2**40).class rescue p [$!.class, $!.message]
p pr.curry(2.5)[1][2] rescue p [$!.class, $!.message]
p method(:puts).curry(1r).arity rescue p [$!.class, $!.message]
