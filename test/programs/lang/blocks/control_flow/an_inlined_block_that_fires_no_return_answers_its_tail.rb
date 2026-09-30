# Inlined block that falls through (no return fires) -- its tail is the value.
def all_fall_through
  proc { [1, 2, 3].each { |x| x * 10 }; :fell }.call
end
p all_fall_through

