# An ivar's first write is an Integer (or nil) literal, and a later
# write assigns an object. A read gives the object, and a call on it
# runs the object's method.

class T_widen_int_obj_to_poly_Box
  def initialize(n)
    @n = n
    @arr = []
    @arr << n
  end
  attr_reader :n
end

class T_widen_int_obj_to_poly_Holder
  def initialize
    @poly = 10              # an Integer first
    @poly = T_widen_int_obj_to_poly_Box.new(5)      # …then an object
  end
  attr_reader :poly
end

# calls T_widen_int_obj_to_poly_Box#n on the object in @poly
puts T_widen_int_obj_to_poly_Holder.new.poly.n      # 5
