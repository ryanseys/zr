# Arithmetic on a Bignum read back from a mixed array uses Bignum arithmetic.
b = 1
i = 0
while i < 70
  b = b * 2
  i = i + 1
end
arr = [b, "x"]      # heterogeneous -> arr[0] is a Bignum
x = arr[0]
puts(x + 1)
puts(x - 1)
puts(x * 2)
puts(x + x)
