# map (a collecting block) inside a proc, no return.
def doubled_array
  proc { [1, 2, 3].map { |x| x * 2 } }.call
end
p doubled_array

