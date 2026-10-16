def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end
t(:f1) { [0.1 + 0.2, 1e100, 1.0 / 3, -0.0, 2.0**70, 1e-7, 123456789.123456789, 1e16, 9007199254740993.0] }
t(:f2) { [Float::MAX, Float::MIN, Float::EPSILON, Float::NAN.to_s, -Float::INFINITY] }
t(:round) { [2.5.round, 3.5.round, 2.675.round(2), 1.15.round(1), 12345.6789.round(-2), 1.5.round(half: :even), 25.round(-1, half: :even), 0.5.floor, -0.5.ceil, 1.23456.floor(3), 1.0e20.to_i] }
t(:fmt) { ["%.10f" % 1.1, "%e" % 12345.678, "%g" % 1e-5, "%a" % 1.0, "%08.3f" % -3.14159, "%x" % 255, "%-5d|" % 3, "%+d" % 5, "%b" % -5, "%o" % 8, "%c" % 65, "%%", "%s %p" % ["a", :b], "%.3s" % "abcdef", "%*d" % [5, 1], "%<a>s %{b}" % {a: 1, b: 2}] }
t(:big) { [2**200, (2**200).to_s(36), -(3**100) / 7, (3**100) % -7, (2**100).pow(3, 10**9 + 7), Integer.sqrt(10**40), (10**30).digits.size, 100.digits(16), (2**64).bit_length, ~(2**65), (2**65) >> 3, -(2**65) >> 100] }
t(:big_ops) { a = 12345678901234567890123; b = 98765432109876543210; [a * b, a / b, a.fdiv(b), a.gcd(b), a.lcm(b), a ** 3, a.coerce(1), Math.sqrt(a), a.to_f, (a * 1.0).to_r] }
t(:rat) { [Rational(3, 6), 1/3r, 0.75.to_r, 0.1.rationalize(Rational(1, 100)), Rational("2/4"), 3.to_r ** -2, Rational(7, 2).round, Rational(5, 2).round(half: :even), 1.5r.floor, Rational(1, 3).to_f] }
t(:cpx) { [Complex(1, 2) * Complex(3, 4), Complex("1+2i"), Complex(3, 4).abs, Complex(1, 0) ** 0.5, Complex::I ** 2, Complex(1, 2).rectangular, Complex.polar(1, Math::PI / 2).real.round(10), 2i] }
t(:int) { [10.pow(-2), 7.divmod(-2), -7.remainder(2), 7.fdiv(2), 255.to_s(2), "0b1010".to_i(0), "1_000".to_i, Integer("0x1f", exception: false), 10.ceildiv(3), 3.14.to_i, 1.0.to_i, 5.clamp(..3), Integer.try_convert("1")] }
t(:math) { [Math.log(8, 2), Math.cbrt(27), Math.hypot(3, 4), Math.gamma(5), Math.lgamma(-0.5), Math.erf(1), Math.atan2(-0.0, -1), Math.log2(2**1000), Math.log10(10**400), (Math.sqrt(-1) rescue $!.class)] }
t(:str_to_f) { ["1.5e3".to_f, "  12abc".to_f, "0x1p3".to_f, Float("0x1p3"), "1e400".to_f, "-.5".to_f, (Float("1.") rescue $!.message), "1_0.5".to_f] }
t(:float_to_s) { [1.0e15, 1.0e16, 123e-20, 5e-324, 1.7976931348623157e308, 100.0, 1.0e-4, 0.0001234].map(&:to_s) }
t(:randomness) { r = Random.new(42); [r.rand, r.rand(100), r.rand(1.5), r.bytes(4).bytes, r.rand(1..6), Random.new(1).rand(2**100)] }
t(:srand) { srand(5); [rand(10), rand, [1, 2, 3, 4].shuffle(random: Random.new(3)), [1, 2, 3].sample(random: Random.new(9))] }
t(:numeric_step) { [1.step(10, 3).to_a, 1.0.step(2.0, 0.5).to_a, (1..2).step(0.5).to_a, 10.downto(7).to_a, 1.step(by: 2, to: 7).to_a, ((1..10) % 3).to_a] }
t(:coerce) { c = Class.new { def coerce(o) = [o, 10] }; [5 + c.new, 5 * c.new, (5 <=> c.new)] }
