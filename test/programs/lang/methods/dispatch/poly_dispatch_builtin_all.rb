# A value that can be an Integer, Float, String or Symbol array, or a
# user-class instance. `length` / `size` answer for each class, and
# `puts` / `to_s` on such a value print the array's contents.

# `length` on each built-in array type answers an Integer.
def lenof(a)
  a.length
end

class Box
  def length; 99; end
end

puts lenof([1, 2, 3])         # 3   (Integer array)
puts lenof([1.0, 2.0, 3.0])   # 3   (Float array)
puts lenof(["a", "b", "c"])   # 3   (String array)
puts lenof([:x, :y])          # 2   (Symbol array)
puts lenof(Box.new)           # 99  (user-class branch)

# `p` on each element of a mixed array prints the element's own value.
mixed = [1, 2.0, "x"]   # mixed element types
mixed.each { |e| p e }
# 1
# 2.0
# "x"
