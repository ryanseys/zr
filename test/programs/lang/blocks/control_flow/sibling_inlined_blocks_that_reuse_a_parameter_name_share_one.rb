# Sibling inlined blocks reusing a param name share one declaration.
def sibling_param_reuse
  proc { [1, 2].each { |x| return x if x == 2 }; [3, 4].each { |x| return x }; 0 }.call
end
p sibling_param_reuse

