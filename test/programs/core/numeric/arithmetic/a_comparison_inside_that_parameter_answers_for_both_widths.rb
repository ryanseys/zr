# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

def cmp(a, b)
  a > b
end
p cmp(5, 2**80)
p cmp(2**80, 5)

