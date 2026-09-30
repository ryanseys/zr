# bare return yields nil
def bare
  proc { return }.call
  "after"
end
p bare.inspect

