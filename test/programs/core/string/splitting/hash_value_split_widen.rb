# `h = {}; h[pa[i]] = pb[i]` inside a method body, where both `pa` and
# `pb` come from `split`. The hash maps String keys to String values.

def build_str_str(a, b)
  pa = a.split("/")
  pb = b.split("/")
  h = {}
  i = 0
  while i < pa.length
    h[pa[i]] = pb[i]
    i += 1
  end
  h
end

r = build_str_str("a/b", "x/y")
puts r["a"]
puts r["b"]
