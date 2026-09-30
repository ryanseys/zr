# `@arr = [a, b]` with objects of one class, then `@arr[i] = v` with a
# String. The Array holds both classes, and its length stays 2.

class T_poly_array_slot_literal_Pad
  def initialize(n)
    @n = n
    @arr = []
    @arr << n
  end
  attr_reader :n
end

class T_poly_array_slot_literal_Holder
  def initialize
    @pads = [T_poly_array_slot_literal_Pad.new(10), T_poly_array_slot_literal_Pad.new(20)]
    @pads[0] = "x"   # a String in an Array of Pads
  end
  attr_reader :pads

  def count
    @pads.length
  end
end

puts T_poly_array_slot_literal_Holder.new.count    # 2
