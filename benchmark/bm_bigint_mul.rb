# Products of long Integers: equal factors from 50 to 6,000 limbs of
# 30 bits, squares, and unequal ones, which split by Karatsuba's method
# above a few dozen limbs.
sum = 0
[50, 200, 800, 3_000, 6_000].each do |limbs|
  a = (3**((30 * limbs) / 1.585).floor) | 1
  b = (7**((30 * limbs) / 2.81).floor) | 1
  rounds = 600_000 / limbs / 4
  rounds.times do
    sum += (a * b) & 0xFFFF
    sum += (a * a) >> ((a.bit_length * 2) - 16)
    sum += (a * (b >> (b.bit_length / 3))).bit_length
  end
end
puts sum
