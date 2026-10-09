# Signal names.
# The numeric tower's rules: the Math family, rounding modes, exact comparisons, conversions and Numeric defaults.
def t
  yield
rescue StandardError => e
  e
end
r = ->(x) { x.round(10) }
p r.(Math.sinh(1.0)), r.(Math.asinh(2.0)), r.(Math.acosh(2.0)), r.(Math.atanh(0.5)), Math.atanh(1.0), Math.atanh(-1.0)
p t { Math.atanh(1.5) }, t { Math.acosh(0.5) }, Math.gamma(6.0), r.(Math.gamma(0.5)), Math.gamma(0.0), Math.gamma(172).infinite?, Math.gamma(-0.5), Math.gamma(1), Math.gamma(171.0), Math.gamma(-1.5)
p Math.lgamma(0.5).map { |v| v.is_a?(Float) ? r.(v) : v }, Math.lgamma(-1.0), Math.lgamma(-0.5), Math.lgamma(2.0), t { Math.gamma(-2.0) }
p Math.frexp(8.0), Math.frexp(0.5), Math.frexp(-12.0), Math.frexp(1), Math.frexp(0), Math.frexp(Float::INFINITY)[0], Math.frexp(Float::NAN)[0], Math.ldexp(0.75, 3), Math.ldexp(1, 2000), Math.ldexp(1.0, 2.5)
p r.(Math.erf(0.5)), r.(Math.erfc(0.5)), t { Math.sqrt("x") }, t { Math.sqrt(nil) }, Math.sqrt(Rational(1, 4)), Math.sqrt(2**64), Math.sqrt(-0.0), Math.log(0), t { Math.log(-1) }, Math.log(8, 2), Math.log(2**1000), t { Math.log(1, -1) }, Math.log2(2**2000), Math.log10(10**400)
include Math
p sqrt(16), hypot(3, 4), PI > 3.14
p t { 7.0 % 0.0 }, t { 7.0.remainder(0) }, t { 7.remainder(0.0) }, t { 7.remainder(0) }, t { 0.0.remainder(0.0) }, 7.0.remainder(2.0), 7.remainder(2.5), -7.0.remainder(2), t { 7.0.divmod(0.0) }, 7.0.modulo(2), 7.0.remainder(-2), (-7).remainder(3), 7.remainder(-3)
p 5.clamp(1.0, 3.0), 5.clamp(1, 3.5), t { 5.clamp(0.0 / 0, 2.0) }, t { 5.clamp(1.0, 0.0 / 0) }, t { 5.clamp(10, 2) }, 5.0.clamp(1, 3), 5.clamp(1, nil), 5.clamp(nil, 3), 5.clamp(7, nil), 5.clamp(..3), t { 5.clamp(1, 0.0 / 0) }, t { 5.clamp(0.0 / 0, 2) }
p 0.nonzero?, 42.nonzero?, 0.0.nonzero?, 1.5.nonzero?, (-42).magnitude, (-1.5).magnitude
p 42.allbits?(1.5), t { 42.allbits?("x") }, 42.anybits?(1.5), 42.nobits?(1.5), (5 << 2.9), (100 >> 1.9), t { 5 & 2.0 }, t { 5 & "x" }, t { 5 | 1.5 }, t { 5 << "x" }, t { 5 << nil }, t { 5 << 2**70 }
p t { 5.gcd("x") }, t { 5.gcd(1.5) }, t { 5.lcm(nil) }, 5.gcd(-10), 5.gcd(2**70)
p Integer("0d19"), Integer("0D19"), Integer("0d19", 10), "0d19".to_i(10), "0d19".to_i, Integer(" 0d19 "), t { Integer("0d19", 16) }, t { Integer("0x1f", 10) }, Integer("0b101", 2), Integer("0o17", 8), Integer("017", 8), t { Integer("019") }, "0x1f".to_i(16), "0b11".to_i(2), "0o17".to_i(8), "0x1f".to_i(10)
p 1.9.round, 1234.5.round(-1), 1234.5.round(-1).class, 1.5.ceil(0).class, 1.23.floor(1), 19.9.truncate(-1), 19.9.truncate(-1).class, 1.5.round(half: :even), 2.5.round(half: :even), 2.5.round(half: :down), 2.5.round(half: :up), t { 2.5.round(half: :x) }, 1.25.round(1, half: :even), 1.35.round(1, half: :even), 2.5.round(half: nil), 25.round(-1, half: :even), 35.round(-1, half: :even), 25.round(-1, half: :down), 2.5.round(half: "even"), -2.5.round(half: :even), -2.5.round(half: :down), 2.675.round(2), 0.5.round, -0.5.round, 1.5.round
p Float::INFINITY.numerator, Float::INFINITY.denominator, Float::NAN.numerator, Float::NAN.denominator, 0.5.numerator, -0.75.denominator
n = Float::NAN
p({ n => 1 }[n], [n].include?(n), [n].index(n), n.eql?(n), n.hash == n.hash, n == n, [n] == [n], [n].uniq.size, [1, n].include?(n))
p 0.75.rationalize, 0.1.rationalize, 3.14.rationalize, 0.3.rationalize(0.01), 0.333.rationalize(Rational(1, 100))
p Signal.signame(2.9), Signal.signame(9.99), t { Signal.signame("x") }, Signal.signame(99)
class Deg < Numeric
  attr_reader :v
  def initialize(v) = @v = v
  def <=>(o) = v <=> (o.is_a?(Deg) ? o.v : o)
  def -(o) = Deg.new(v - (o.is_a?(Deg) ? o.v : o))
  def /(o) = Deg.new(v / (o.is_a?(Deg) ? o.v : o))
  def *(o) = Deg.new(v * (o.is_a?(Deg) ? o.v : o))
  def to_f = v.to_f
  def to_i = v.to_i
  def to_r = Rational(v)
  def coerce(o) = [Deg.new(o), self]
  def inspect = "Deg(#{v})"
end
p Deg.new(-7).abs, -Deg.new(7), +Deg.new(-7), Deg.new(7).div(Deg.new(2)), Deg.new(7) % Deg.new(2), Deg.new(7.6).round, Deg.new(7.6).round(1), Deg.new(-7.6).truncate, Deg.new(7).to_int, Deg.new(7).numerator, Deg.new(7).finite?, Deg.new(7).infinite?, Deg.new(2).nonzero?, Deg.new(0).zero?
class Plain < Numeric
  def initialize(v) = @v = v
  def to_f = @v.to_f
  def inspect = "Plain"
end
p Plain.new(1).coerce(Plain.new(2)), Plain.new(1).coerce(3), Plain.new(2).floor, t { Plain.new(2).abs }, t { Plain.new(2).to_int }
p Numeric.method_defined?(:singleton_method_added), Complex(1, 2).respond_to?(:i), Complex(0, 2).abs, Complex(0.0, 2).abs, Complex(3, 4).numerator, Complex(Rational(2, 3), Rational(3, 4)).numerator, Complex(Rational(2, 3), Rational(3, 4)).denominator
p t { 1 + true }, t { 1.5 + :s }, t { "x" + true }, t { [1] + true }, t { 5.coerce(true) }, t { 1.5.coerce([1]) }, t { 1.5.coerce("x") }, 5.coerce("2.5"), t { Integer(true) }
big = 10**100
p [1.0e100 == big, big == 1.0e100], [2**53 + 1 == 2.0**53, 2.0**53 == 2**53 + 1, 2**53 + 1 > 2.0**53, 2.0**53 < 2**53 + 1], [(2**53 + 1) <=> 2.0**53, 2.0**53 <=> (2**53 + 1)], [big <=> 1.0e100, 1.0e100 <=> big, big > 1.0e100, 1.0 / 0 > big, big < Float::NAN]
p "ab" * 2.9, [1, 2] * 2.9, [10, 20, 30][1.7], [1, 2, 3].first(2.9), "abcde"[1.5, 2.9], "10".to_i(2.9), "a".center(10.5), t { "ab"[1..2**70] }, t { [1][2**70] }
a = [1, 2, 3, 4]; a[1.5..2] = 9; p a
s = +"abc"; s[1.7] = "X"; p s
p (10..2).step(-2).to_a, (10...1).step(-1).to_a, (1..10).step(-1).to_a, (10..2).step(-2).size, t { (1.0..10.0).step("x").to_a }, t { ("a".."e").step(:s).to_a }, t { (..5).step(2) { } }, (1..).step(3).first(2)
p 1.upto(3.5).to_a, 3.downto(1.5).to_a, 1.upto(3.5).size, 1.upto(-1.5).to_a, t { 5.pow(-1, 7) }
