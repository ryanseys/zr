# User-defined instance methods named `hash`, `to_i`, `to_s` and
# `length` return the user's value (a String here), not the value of
# the built-in method with that name.
#
# Coverage:
#   - `hash` shadowed -- the bcrypt shape, but in instance form.
#   - `to_s` shadowed -- collides with Object#to_s (string).
#   - `to_i` shadowed -- collides with Integer#to_i.
#   - `length` shadowed -- collides with String#length.

class T_method_name_collision_imeth_Item
  attr_accessor :tag
  def initialize(t); @tag = t; end
  def hash;   "item-hash:"   + @tag; end
  def to_i;   "item-toi:"    + @tag; end
  def to_s;   "item-tos:"    + @tag; end
  def length; "item-length:" + @tag; end
end

i = T_method_name_collision_imeth_Item.new("a")
puts i.hash
puts i.to_i
puts i.to_s
puts i.length
