# A power of two raised to a large exponent is a shift, so a result of
# millions of bits takes no long multiplication.
x = 4**40_000_000
p x.bit_length
p x == 1 << 80_000_000
p (-2)**5, (-2)**6, 8**3, 1**10, 0**5
p (4r**20) == 4**20, (1 / 4r)**3
begin
  4r**400_000_000_000_000_000_000
rescue ArgumentError => e
  p e.message
end
