# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

# the default-value path binds the same slot
def opt(x = 7)
  x.to_s
end
p opt
p opt(2**100)

