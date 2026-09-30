# `arr[i, n] = src` replaces the slice with the rhs, also when arr holds
# values of mixed types.

class C
  def init_arr
    @arr = [10, 20, 30, 40, 50]
  end
  def init_str
    @arr = "scalar"     # widens slot to poly
  end
  def replace
    @arr[1, 2] = [99, 88]
  end
  def at(i); @arr[i]; end
end

c = C.new
c.init_arr
c.replace
puts c.at(0)
puts c.at(1)
puts c.at(2)
