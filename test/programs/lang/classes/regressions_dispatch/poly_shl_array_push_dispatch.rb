# `<<` on an ivar that held nil and then an Integer Array pushes the
# value onto the Array. It is a bit-shift only when the receiver is
# an Integer.

class T_poly_shl_array_push_dispatch_C
  def initialize
    # First `nil`, then an Integer Array.
    @v = nil
    @v = [10, 20, 30]
  end
  def push(x); @v << x; end
  def length; @v.length; end
  def get(i); @v[i]; end
end

c = T_poly_shl_array_push_dispatch_C.new
c.push(99)
c.push(88)
puts c.length         # 5
puts c.get(0)         # 10
puts c.get(3)         # 99
puts c.get(4)         # 88

# Bit-shift on an Integer receiver.
x = 1
puts x << 3           # 8
