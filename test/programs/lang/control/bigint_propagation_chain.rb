# Stress test: bigint propagation through a chain of dependent locals.
# `a` starts as a small Integer and becomes a Bignum by `a = a * 2`
# inside the while loop. The later assignments `b = a + 1`,
# `c = b + 1`, ... each depend on the one before, so each one also
# holds a Bignum.

a = 1
i = 0
while i < 50
  a = a * 2
  i = i + 1
end

b = a + 1
c = b + 1
d = c + 1
e = d + 1
f = e + 1
g = f + 1
h = g + 1

puts a > 0
puts b > 0
puts c > 0
puts d > 0
puts e > 0
puts f > 0
puts g > 0
puts h > 0
puts (h - a) == 7
