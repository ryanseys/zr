# `(a, b = 10, 11)` used as an expression returns the RHS array.
p( (a, b = 10, 11)[1] )
p a
p b

arr = (x, y = "hi", "lo")
p arr[0]
p arr[1]
p x
p y
