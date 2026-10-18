# Integer.sqrt is the floor of the square root, as ruby gives it, for
# small values, exact squares and their neighbours, powers of two on
# both sides, values at the fixnum edge, and long values of thousands of
# limbs, which it finds in a few Newton steps.
p (0..100).map { |n| Integer.sqrt(n) }
[1, 2, 3, 30, 31, 32, 61, 62, 63, 64, 100, 1000, 9000, 50_000].each do |bits|
  r = (3**(bits / 1.585).floor) | 1
  sq = r * r
  p [bits, Integer.sqrt(sq) == r, Integer.sqrt(sq - 1) == r - 1, Integer.sqrt(sq + 1) == r, Integer.sqrt(sq + 2 * r) == r, Integer.sqrt(sq + 2 * r + 1) == r + 1]
  p [Integer.sqrt(1 << bits).to_s(16).size, Integer.sqrt((1 << bits) - 1).bit_length, Integer.sqrt((1 << bits) + 1).bit_length]
end
p Integer.sqrt(2**62 - 1), Integer.sqrt(2**62), Integer.sqrt(2**64), Integer.sqrt(4.9), Integer.sqrt(10**40)
p (Integer.sqrt(-1) rescue $!.class), (Integer.sqrt("4") rescue $!.class)
