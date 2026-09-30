# Multi-value return becomes an array.
def mv
  proc { return 1, 2, 3 }.call
  [9]
end
p mv

