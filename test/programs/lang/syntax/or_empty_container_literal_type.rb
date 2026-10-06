# The empty literal on the right of `||` / `&&` takes the expression's
# container type, as a ternary arm does, whatever the left side holds.
a = ["x"]
p(a || [])
h = { "a" => 1 }
p(h.keys || [])
rows = [{ "a" => 1 }]
p(rows.first.keys || [])
f = [1.5]
p(f || [])
i = [1]
p(i || [])
p(a || ["z"])
p(a && [])
p((nil || []).size)
syms = [:a]
p(syms || [])
objs = [[1], [2]]
p(objs || [])
p((h.values || []).size)
def pick(x) = x || []
p pick(["y"])
p pick(nil).size
