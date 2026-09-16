# Math's functions read a Float, an Integer or another Numeric through
# its to_f, and refuse anything else with ruby's message, whatever
# answers to_f: the check names no function.
class Lengthy
  def to_f = 2.0
end
class Measure < Numeric
  def to_f = 2.0
end
p Math.sin(0), Math.sqrt(16), Math.sqrt(2**70).class, Math.cos(1.0).round(3), Math.log(Measure.new).round(3), Math.hypot(3, 4)
p (Math.log(Lengthy.new) rescue [$!.class, $!.message]), (Math.sin(nil) rescue [$!.class, $!.message]), (Math.sqrt("4") rescue [$!.class, $!.message])
p (Math.cos(:a) rescue [$!.class, $!.message]), (Math.sqrt(-1) rescue [$!.class, $!.message]), (Math.atan2(nil, 1) rescue [$!.class, $!.message])
p Math.exp(0), Math.cbrt(27), Math.sin(2**62).finite?, Math.sqrt(Rational(1, 4)), Math.log2(8), Math.log10(1000), Math.log(8, 2), (Math.log(-1) rescue $!.class)
sum = 0.0
1.upto(200_000) { |i| sum += Math.sin(i) * Math.cos(i) + 1.0 / Math.sqrt(i) }
p sum.round(6)

__END__
0.0
4.0
Float
0.54
0.693
5.0
[TypeError, "can't convert Lengthy into Float"]
[TypeError, "can't convert nil into Float"]
[TypeError, "can't convert String into Float"]
[TypeError, "can't convert Symbol into Float"]
[Math::DomainError, "Numerical argument is out of domain - sqrt"]
[TypeError, "can't convert nil into Float"]
1.0
3.0
true
0.5
3.0
3.0
3.0
Math::DomainError
892.933959
