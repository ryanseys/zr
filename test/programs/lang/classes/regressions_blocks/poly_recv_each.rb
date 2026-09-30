# `.each` on an ivar `@store` that two methods set to different
# Arrays: an Integer Array, and an Array filled with Strings. The
# block runs for each element of the Array that `@store` holds.

class T_poly_recv_each_C
  def store_int_array
    @store = [10, 20, 30]
  end
  def store_poly_array
    @store = [nil] * 3
    @store[0] = "a"
    @store[1] = "b"
    @store[2] = "c"
  end
  def visit
    @store.each do |x|
      puts x.to_s
    end
  end
end

c = T_poly_recv_each_C.new
c.store_int_array
c.visit
puts "---"
c.store_poly_array
c.visit
