# An array can hold a `Method` object in one element and an
# Integer array in another. `@arr[i][j]` then calls `[]` on the
# element: a Method calls the method, and an Array indexes. A CPU
# emulator dispatches memory reads in this shape, `@fetch[a][a]`.

class C
  def peek(addr); 42; end
  def setup
    @arr = [nil] * 16
    range = [10, 20, 30, 40, 50, 60, 70, 80]
    @arr[5] = range            # IntArray
    @arr[10] = method(:peek)   # Method
  end
  def call_via(addr)
    (@arr[addr][addr & 0xff]).to_i
  end
end

c = C.new
c.setup
puts c.call_via(10)            # via Method peek_X → 42
puts c.call_via(5)             # via IntArray range → range[5] = 60
