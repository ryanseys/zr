# Multi-assignment into two attr targets (`b.x, b.y = b.y, b.x`, the
# idiomatic in-place swap) must call each setter correctly, and swap
# the values. Array-index multi-assign targets (`arr[0], arr[1] =
# ...`) must work too.

arr = [1, 2, 3, 4]
arr[0], arr[1] = arr[1], arr[0]
puts arr[0]
puts arr[1]

class Box
  attr_accessor :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
end
b = Box.new(1, 2)
b.x, b.y = b.y, b.x
puts b.x
puts b.y
