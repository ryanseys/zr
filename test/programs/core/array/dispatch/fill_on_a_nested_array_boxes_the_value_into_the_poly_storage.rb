# `arr.fill(val)` on an array with mixed element types sets every
# element to `val`.

def make_arr
  arr = [1, "two", 3.14]   # heterogeneous elements
  arr.fill(42)
  arr
end

p make_arr   # [42, 42, 42]
