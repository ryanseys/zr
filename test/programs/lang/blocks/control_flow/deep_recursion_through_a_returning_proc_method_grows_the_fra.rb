# Deep recursion through a returning-proc method: the frame stack grows past the
# old fixed cap (256) rather than raising SystemStackError.
def countdown_to_zero(n)
  return n if n <= 0
  proc { return countdown_to_zero(n - 1) }.call
end
p countdown_to_zero(2000)

