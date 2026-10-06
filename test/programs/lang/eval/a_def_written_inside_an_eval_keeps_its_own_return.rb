# The catch belongs to the method the eval stands in. A `def` the eval writes
# is a method of its own, so its `return` leaves it and no more: `outer` runs
# on to its last statement.

def outer
  instance_eval("def inner; return :inner; end")
  [inner, :outer]
end

p outer
