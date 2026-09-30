# Fall-through value: a returning proc that does NOT return still yields its tail
# expression (the `.call` result is the method's value). Mixed return/tail types
# unify to a poly home; same-type stays scalar.
def tail_or_ret(n)
  proc { return 99 if n < 0; "tail" }.call
end
p tail_or_ret(5)
p tail_or_ret(-1)

