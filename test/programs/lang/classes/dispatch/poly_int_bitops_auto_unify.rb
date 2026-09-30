# Same operator-site auto-unbox, but for bit operators (`<<`,
# `>>`, `&`, `|`, `^`), with an Integer receiver and an argument
# of unknown type.

# Heterogeneous array of [user-class-with-[], Integer array] —
# the outer `arr[i]` gives a value of unknown type, and `[j]` on
# it also gives a value of unknown type.
class Bits
  def [](i); [0xff, 0x0a, 0x10][i]; end
end

arr = [Bits.new, [0xff, 0x0a, 0x10]]

# Each `arr[k][j]` is `int + poly` style: addr is int, the
# heterogeneous dispatch result is statically poly.
puts(1   << arr[1][1])     # 1 << 0x0a = 1024
puts(0xf0 & arr[1][0])     # 0xf0 & 0xff = 0xf0 = 240
puts(0x05 | arr[1][1])     # 0x05 | 0x0a = 0x0f = 15
puts(0xff ^ arr[1][2])     # 0xff ^ 0x10 = 0xef = 239
puts(arr[1][1] >> 1)       # 0x0a >> 1 = 5
