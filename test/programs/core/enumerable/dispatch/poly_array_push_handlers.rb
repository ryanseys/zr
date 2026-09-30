# `<<` and `push` on a mixed-element array append the value.
#
# The array starts as a mixed literal. Then `arr << v` and
# `arr.push(v)` both add an element.

arr = [1, "two", :three]
arr << 42
arr.push("four")
puts arr.length
puts arr[0]
puts arr[1]
puts arr[2]
puts arr[3]
puts arr[4]
