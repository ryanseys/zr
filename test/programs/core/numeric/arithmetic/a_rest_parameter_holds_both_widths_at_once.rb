# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

def rest(*xs)
  xs.map { |v| v.to_s }
end
p rest(1, 2**70)

