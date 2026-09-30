# `Array#delete_at(i)` on an array of user-class instances removes
# and returns the element. Tep::Scheduler's fiber-slot list uses it
# in a `clear` loop.

class T_ptr_array_delete_at_Box
  attr_accessor :tag
  def initialize(tag)
    @tag = tag
  end
end

a = [T_ptr_array_delete_at_Box.new("seed")]
a.delete_at(0)
a.push(T_ptr_array_delete_at_Box.new("a"))
a.push(T_ptr_array_delete_at_Box.new("b"))
a.push(T_ptr_array_delete_at_Box.new("c"))
puts a.length.to_s     # 3

# Remove from middle.
v = a.delete_at(1)
puts v.tag             # b
puts a.length.to_s     # 2
puts a[0].tag          # a
puts a[1].tag          # c

# Negative index counts from end.
last = a.delete_at(-1)
puts last.tag          # c
puts a.length.to_s     # 1

# Out-of-range index returns nil; array unchanged.
gone = a.delete_at(99)
puts gone.nil? ? "nil" : "not-nil"
puts a.length.to_s     # 1

# Drain via repeated delete_at(0). The loop must end.
while a.length > 0
  a.delete_at(0)
end
puts a.length.to_s     # 0
puts a.empty? ? "empty" : "not-empty"
