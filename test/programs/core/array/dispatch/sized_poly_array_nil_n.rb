# `@arr = [nil] * N` makes an array of nils. The ivar also gets a
# String and an Integer in other methods. Later writes of a
# String, an Integer and a Symbol into the array keep each value
# and its class.

class C
  def init_arr_widen
    @arr = [nil] * 8
    @arr[0] = "string-payload"
    @arr[1] = 42
    @arr[2] = :sym
  end
  def init_str
    @arr = "scalar"
  end
  def init_int
    @arr = 7
  end
  def at(i)
    @arr[i]
  end
end

c = C.new
c.init_arr_widen
puts c.at(0).to_s   # "string-payload"
puts c.at(1).to_i   # 42
puts c.at(2).to_s   # "sym"
