# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

# keyword and splat arguments reach it too
def kw(x:, y: 3)
  (x + y).to_s
end
p kw(x: 1)
p kw(x: 2**90, y: 2)

