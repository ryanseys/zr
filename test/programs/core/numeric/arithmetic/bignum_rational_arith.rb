# big Rational arithmetic and comparison. One operand is already a big Rational,
# and the other numeric operand becomes a Rational with Bignum parts.
r = (10**30).to_r
p(r + (1r/3))
p(r - r)
p(r * 2)
p(r / 2)
p(r + 1)
p((10**30).quo(3) + (10**30).quo(6))
p((10**30).quo(3) * 3)
p(r <=> (10**30).to_r)
p(r <=> (10**31).to_r)
p(r > (10**29).to_r)
p(r < (10**31).to_r)
p((2**70).quo(2**69) == 2)
p(r == (10**30).to_r)
p(r.to_f)
p([(10**30).to_r, (1r/2), (10**20).to_r].sort)
