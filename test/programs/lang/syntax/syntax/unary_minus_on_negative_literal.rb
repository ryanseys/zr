# `-(-7)` puts two minus signs side by side on a literal. The negation of a
# negative literal answers the positive value, for Integer and Float.
p(-(-7))
p(- -7)
p(-(-3.5))
p(-(-(-7)))
p(-(-7) + 1)
x = -(-2)
p x

# the same doubling with a plus, and the mixed pairs that were never ambiguous
p(+(+7))
p(-(+7))
p(+(-7))
p(+(+2.5))

# a bignum negates through its own helper, not a C sign
p(-(2**70))
p(-(-(2**70)))

# and the ordinary spellings keep their tight form
a = -7
p(-a)
p(-7)
p(- 7)
