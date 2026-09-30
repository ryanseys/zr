# to_r / rationalize / quo on a Bignum build a big Rational (the numerator
# is more than 64 bits). This checks construction, inspect/to_s/puts, to_f,
# class, and ==, and also a Rational with small parts.
p((10**30).to_r)
p((10**30).rationalize)
p((10**30).quo(3))
p((10**30).quo(2**64))
p((-(10**30)).to_r)
p((10**30).to_r.to_f)
p((10**30).to_r.class)
p((10**30).to_r == (10**30).to_r)
p((10**30).to_r == (10**31).to_r)
puts((10**30).quo(7))
a = [(10**30).quo(7), (10**40).to_r]
p a
# a Rational with small parts
p((1r/3))
p(3.to_r)
p((1r/2) + (1r/3))
p(2.quo(3))
p(0.5.to_r)
