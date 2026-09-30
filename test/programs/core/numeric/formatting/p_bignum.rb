# `p` of a bignum-producing expression must print the integer, just as
# `puts`/`print` do (Integer#inspect == #to_s).
p(10**30)
p(2**100)
p(10 ** 20 + 1)
p(2**64)
p(3**50)
