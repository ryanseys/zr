# `@arr = [nil] * N`, then `@arr[i] = v` writes of an Integer and a
# String. The Array holds the mixed values, and its length stays N.

class T_poly_array_slot_sized_default_Holder
  def initialize
    @arr = [nil] * 3
    @arr[0] = 42      # int
    @arr[1] = "two"   # a String — the Array now holds mixed classes
  end
  attr_reader :arr

  def count
    @arr.length
  end
end

puts T_poly_array_slot_sized_default_Holder.new.count   # 3
