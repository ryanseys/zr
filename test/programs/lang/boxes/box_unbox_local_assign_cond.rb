# `if (entry = @arr[i])` tests the value of the assignment. The array
# holds values of mixed types, and the test uses Ruby truthiness.

class C
  def initialize
    @arr = [10, "twenty", :thirty]   # mixed types
  end
  def find(i)
    if (entry = @arr[i])             # entry can hold any of the element types
      entry
    end
  end
end

c = C.new
puts c.find(0).to_s
puts c.find(1).to_s
