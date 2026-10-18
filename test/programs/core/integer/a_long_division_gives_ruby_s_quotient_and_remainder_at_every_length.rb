# divmod, div, %, remainder and to_s of long Integers answer as ruby
# does where a division recurses (divisors and quotients of thousands of
# limbs): divisors of odd and even bit lengths, exact multiples,
# remainders of zero and of one less than the divisor, every sign, and
# the decimal digits of long values, which split by such divisions.
require "zlib"

out = []
[1000, 1001, 1500, 2047, 3001].each do |limbs|
  b = (7**((30 * limbs) / 2.81).floor) | 1
  b2 = b >> 7
  [1001, 1800, 4000].each do |qlimbs|
    q = (3**((30 * qlimbs) / 1.585).floor) + 5
    [b, b2, b + 1, (1 << (30 * limbs)) - 1].each do |d|
      [q * d, q * d + 1, q * d - 1, q * d + d - 1, -(q * d) - 3].each do |a|
        qq, r = a.divmod(d)
        out << qq.to_s(36) << r.to_s(36) << (a.div(-d)).to_s(36) << (a % -d).to_s(36) << a.remainder(d).to_s(36)
        out << (qq * d + r == a) << (r >= 0 && r < d)
      end
    end
  end
end
puts out.size, Zlib.crc32(out.join(","))
x = (3**60_000) + 7
s = x.to_s
p s.size, s[0, 30], s[-30..], Zlib.crc32(s), Integer(s) == x, x.to_s(7).size
