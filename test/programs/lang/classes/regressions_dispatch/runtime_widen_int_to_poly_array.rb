# `@arr[i] = v` puts a String into an Integer Array held by an ivar
# that another method sets to a String. The element keeps the String,
# and the other elements keep their Integers.

class T_runtime_widen_int_to_poly_array_C
  def init_arr_widen
    @arr = [10, 20, 30]   # an Integer Array
    @arr[1] = "string!"   # a String element
  end
  def init_str
    @arr = "scalar"       # a String in the same ivar
  end
  def at(i); @arr[i]; end
end

c = T_runtime_widen_int_to_poly_array_C.new
c.init_arr_widen
puts c.at(0)               # 10
puts c.at(1)               # "string!"
puts c.at(2)               # 30
