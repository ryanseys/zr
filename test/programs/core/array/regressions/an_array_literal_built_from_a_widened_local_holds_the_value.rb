# A local can hold an Integer or a String, because two branches set it.
# An `[x]` literal of that local holds the value itself.

addr = 7
flag = 0
if flag > 0
  # This path does not run. It only lets `addr` also be a String.
  addr = "x"
end

# `addr` can be a String or an Integer, but at run time it is 7.
# The `[addr]` literal holds that 7.
arr = [addr]
puts arr.length          # 1
puts arr[0]              # 7
