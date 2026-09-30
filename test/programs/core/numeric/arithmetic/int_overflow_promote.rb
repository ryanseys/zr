# `x *= y` inside a while loop gives the full arbitrary-precision
# Ruby answer, not a wrapped int64. A value just past 2^63 prints
# as a positive number: `2**63` is `9223372036854775808`.

# 2**63 -- the first value past the int64 range.
m = 1
i = 0
while i < 63
  m = m * 2
  i = i + 1
end
puts m

# 2**100 -- deeper into multi-limb territory.
m = 1
i = 0
while i < 100
  m = m * 2
  i = i + 1
end
puts m

# Factorial of 25 -- classic bigint, well past int64.
n = 1
i = 1
while i <= 25
  n = n * i
  i = i + 1
end
puts n
