# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

def arith(n)
  n * 2 + 1
end
p arith(3)
p arith(2**70)

