# conditional: returns non-locally only when the guard holds
def cond(x)
  proc { return "yes" if x > 0 }.call
  "no"
end
p cond(5)
p cond(-1)

