# An Integer times itself gives the product ruby gives, at every length:
# both sides of each length where the product splits in halves, limbs of
# all ones (the largest carries), negative values, a power of two, and
# `**` and Integer.sqrt, which square too.
require "zlib"

out = []
[2, 3, 10, 31, 32, 33, 47, 63, 64, 65, 66, 127, 128, 129, 200, 513, 1500].each do |limbs|
  bits = limbs * 30
  ones = (1 << bits) - 1
  odd = (3**(bits / 1.585).floor) | 1
  [ones, ones - 1, odd, -odd, 1 << (bits - 1), (1 << (bits - 1)) + 1, odd ^ (ones >> 1)].each do |x|
    out << x * x << x * x.abs << (x**2) << (x * x == x * (x + 0))
  end
  out << Integer.sqrt(odd * odd) << (odd**3)
end
puts out.size, Zlib.crc32(out.map { |v| v.is_a?(Integer) ? v.to_s(16) : v.to_s }.join(","))
x = 2**300 + 12345
p x * x - (x * (x + 1) - x), ((2**2000 - 1)**2).bit_length, ((7**900) * (7**900)) == 7**1800
