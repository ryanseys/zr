# Cospi has no wasm shim.
# Bignums: arithmetic, division, bits, conversions, formatting and the numeric tower past the fixnum range.
a = 2**64
p a, a.class, a + 1, a - 1, a * a, a / 3, a % 3, -a, a <=> 1.5
p 18446744073709551616, 4611686018427387903 + 1, 4611686018427387904 - 1, (2**62).class
p 10**25, (10**25).to_s(16), (10**25) / (10**12), (10**25) % (10**12), (10**25).divmod(-7), (-(10**25)).divmod(7)
p a.to_f, (2**53 + 1).to_f, (2**1024).to_f
p a == a.to_f, 1.5 + a, a > 1e19, a < 1e20
p a & 0xff, a | 1, a ^ a, ~a, -a & 0xff, a >> 3, a << 3, -a >> 3, (-(2**70) + 1) >> 3
p a.hash == (2**64).hash, a.eql?(2**64), a.equal?(2**64), a == 2**64, [a].include?(2**64), { a => 1 }[2**64]
p a.bit_length, (-a).bit_length, a[64], a[63], a.digits(1000).first(2), a.even?, a.odd?, a.zero?, a.abs, (-a).abs
p a.pow(3, 1000), a ** 2, 2 ** 100, (2**100).to_s(36), Integer.sqrt(a), a.gcd(2**35 * 3), a.fdiv(3)
p "18446744073709551616".to_i, Integer("18446744073709551616"), "0x10000000000000000".hex
p 1e30.to_i, -1e30.to_i, (1e30.to_i).to_f == 1e30
p (1..3).reduce(1) { |m, i| m * (2**40) }, 25.downto(20).reduce(:*) * 10**20
p a.coerce(3), 3.coerce(a), a.coerce(1.5)
p Rational(a, 3), Rational(a, 3) + 1, (a.to_r / 7).round(2)
p (2**64).size, (2**100).size
p [2**70, 3, 2**65].sort, [2**70, 3, 2**65].max, (2**64..2**64 + 2).to_a
p 12345678901234567890 * 98765432109876543210
p (2**200) / (2**100 + 1), (2**200) % (2**100 + 1)
p format("%d", a), "#{a}", a.inspect
a = 2**64
p format("%x %o %b %20d %-25d| %+d %e", a, a, a, a, a, a, a)
p a.to_s(2), a.to_s(8), (-a).to_s(16), a.to_s.size
p (1..30).reduce(:*), 100.downto(1).reduce(:*).to_s.size
p a.round(-5), a.floor(-19), a.ceil(-19), a.truncate(-3), a.round(2)
p a.pred, a.succ, a.next, a.integer?, a.finite?, a.infinite?, a.real?, a.positive?, a.negative?, (-a).positive?
p a.chr rescue p $!
p a.times.size, a.upto(a + 2).to_a, (a + 2).downto(a).to_a
p a.divmod(7), a.div(7), a.modulo(7), a.remainder(-7), (-a).remainder(7), a.fdiv(7.0)
p a.pow(2), a.pow(-1), a ** -1, a ** 0.5, 2 ** 0.5, (-8) ** (1.0/3) rescue p $!
p a.lcm(6), a.gcdlcm(6), a.digits.size, a.digits(16), a.bit_length, a.allbits?(3), a.anybits?(1 << 64), a.nobits?(1)
p a.between?(1, 2**65), a.clamp(1, 5), a <=> 2**65, (2**65 <=> a), a <=> a, a <=> "x"
p a.zero?, 0 == a - a, (a - a).class, (a / a).class, (a * 0).class, (a >> 100), (a >> 100).class, 1 << 64, 1 << 64 >> 64
p Math.sqrt(a), Math.log(a), Math.log2(a), Math.log10(a), Math.cbrt(a)
p a.to_r, a.to_c, Rational(a, a + 1), Complex(a, 1) * 2, a.rationalize, a.numerator, a.denominator
p Integer("0b" + "1" * 70, 0), "1" * 70 == ("1" * 70).to_i.to_s, ("9" * 30).to_i + 1, "-#{"9" * 30}".to_i, "  123456789012345678901234567890abc".to_i
p [a, a].pack("Q>Q<").bytes.size, [a - 1].pack("Q").unpack1("Q") == a - 1, [a].pack("w").unpack1("w") == a
p a.hash.class, {a => 1, a + 1 => 2}.size, [a, a + 1, a].uniq.size, [a, 2**64].tally
p Random.new(a).rand(10), Random.new(2**100).rand.class, Random.rand(a).class
p (a..a + 5).step(2).to_a, (1..a).size, (a..).first(2), (a...a + 3).sum, (a..a + 3).minmax
p [a, 1, -a, 2**63].sort, [a, 1, -a].min, [a, 1, -a].max, [a, 1].sum, [a, 1.5].sum, [a] * 2 == [a, a]
p a.coerce(2.5), a.coerce(Rational(1, 2)) rescue p $!
p a.instance_of?(Integer), a.is_a?(Comparable), a.frozen?, a.dup.equal?(a), a.itself == a, a.object_id.class, a.singleton_methods
p 123456789012345678901234567890 % 97, 123456789012345678901234567890.to_s(36), 2**64 - 2**64 + 5
def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)
p (1..100).reduce { |x, y| x * y } / (1..98).reduce { |x, y| x * y }
x = 1; 100.times { x *= 3 }; p x, x % 1000007, x.to_s.size, x.to_f
p (10**20).to_s(2).count("1"), (10**20) & (10**20 - 1), (10**20) | 1, (10**20) ^ (10**19), ~(10**20)
p -(2**64) / 3, -(2**64) % 3, (2**64) / -3, (2**64) % -3, (-(2**64)).divmod(-3), -7 / (2**64), -7 % (2**64), 7 % -(2**64)
p((2**64) == (2**64).to_f, (2**64 + 1) == (2**64).to_f, (2**64).eql?((2**64).to_f), 1e19.to_i, 1e19.floor, 1.5e19.ceil, -1e19.round, 1e19.truncate)
p (2**64).to_f.to_i == 2**64, 3.0e40.to_i.to_s.size, (2**64 + 0.5).class rescue p $!
