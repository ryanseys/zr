# A Float compared with a Bignum keeps its full range, so `1.0 / 0 > 10 ** 100`
# is true.
#
# Ordering compares as doubles. Equality is decided exactly, because 1.0e100
# and 10 ** 100 differ by one ulp and as doubles would compare equal.
big = 10 ** 100
p(1.0e200 > big)
p(1.0e50 > big)
p(1.0 > big)
p(big > 1.0)
p(big > 1.0e200)
p(1.0 / 0 > big)
p(-1.0 / 0 < big)
p(2.5 < 10 ** 30)
p(big <= 1.0e200)
p(big >= 1.0e200)
p(1.0e200 <=> big)

p(1.0e100 == big)
p(big == 1.0e100)
p(big != 1.0e100)
p(1.0e200 == big)
p(big.to_f == big)
p(1.5 == big)
p(1.0 / 0 == big)
p(2.0 == 2 ** 1)
p(2.0 == 2 ** 70)
p((2 ** 70).to_f == 2 ** 70)
