# `@arr[i] = v` on an ivar that other methods set to a String or an
# Integer. When @arr holds an Array (`[nil] * N`), the write goes into
# that Array.

class T_poly_recv_bracket_assign_C
  def init_arr(n)
    @arr = [nil] * n      # an Array
    @arr[0] = 100
  end
  def init_str
    @arr = "scalar"       # a String
  end
  def init_int
    @arr = 42             # an Integer
  end
  def at(i)
    @arr[i]
  end
end

c = T_poly_recv_bracket_assign_C.new
c.init_arr(3)
puts c.at(0)              # 100
