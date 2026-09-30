# `Integer#[N]` returns bit N (0-indexed from the LSB) of the
# integer, the same as `(n >> N) & 1`.

# Static index
n = 0b10110100
puts n[0]    # 0
puts n[1]    # 0
puts n[2]    # 1
puts n[3]    # 0
puts n[4]    # 1
puts n[5]    # 1
puts n[6]    # 0
puts n[7]    # 1

# Dynamic index
i = 0
while i < 4
  puts n[i]
  i += 1
end
# 0 0 1 0
