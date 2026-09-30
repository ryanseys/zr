# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

def any(x)
  x.to_s
end
p any(1)
p any(2**200)

