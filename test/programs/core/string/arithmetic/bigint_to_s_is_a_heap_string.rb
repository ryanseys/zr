# Integer#to_s on a Bignum answers an ordinary String, with the correct
# length, and a concat on it copies only its own bytes.
#
# Interleaving other allocation is the point: it changes what sits in
# memory next to the string.

big = 2**200
noise = []

s = big.to_s
p s.length
p s[0, 3]
p s.bytesize

# through concat, the shape that overran
20.times do |i|
  noise.push("filler-#{i}-#{'x' * i}")
  t = (2**200 + i).to_s + "-" + (2**64 + i).to_s
  p t if i == 19
end

# the same value reached through the poly path (a container read is poly)
mixed = [big, "s"]
p mixed[0].to_s.length
p mixed[0].to_s + "!"

# a BigRational renders by concatenating two of these
r = Rational(2**100, 3)
p r.to_s
p r.inspect

# and the small-value fast path inside the same function
p (2**64).to_s
p (-(2**64)).to_s
p noise.length
