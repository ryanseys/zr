# Nested returning-proc methods: inner's return unwinds only inner.
def inner
  proc { return "inner-ret" }.call
  "inner-normal"
end
def outer
  x = inner
  proc { return "outer:#{x}" }.call
  "outer-normal"
end
p outer

