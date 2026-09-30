# `(arr[idx] ||= []) << v` — chained `||=` over an Array element.
# The `||=` expression gives the element, so `<<` appends to the
# element in the Array.

class T_chained_or_assign_collection_poly_array_C
  def initialize
    @a = Array.new(3) { [] }    # an Array of empty Arrays
  end
  def push(idx, v)
    (@a[idx] ||= []) << v
  end
  def count(i); @a[i].length; end
end

c = T_chained_or_assign_collection_poly_array_C.new
c.push(0, 10)
c.push(0, 20)
c.push(1, 100)
puts c.count(0)   # 2
puts c.count(1)   # 1
puts c.count(2)   # 0
