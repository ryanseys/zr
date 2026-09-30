# Data#with sets a member from a value whose type is known only at run time,
# such as an element of a mixed Array. It works as the regular `.new` call does.
M = Data.define(:entry, :xs)
m = M.new(entry: "", xs: [])
msg = [:entry, "hi"]              # a heterogeneous [Symbol, String] array
p m.with(entry: msg[1]).entry     # msg[1] is the array's union (poly) element

N = Data.define(:n, :f, :x)
nn = N.new(n: 0, f: 0.0, x: 0)
ints = [10, 20]
flts = [1.5, 2.5]
p nn.with(n: ints[0]).n           # poly -> Int member
p nn.with(f: flts[1]).f           # poly -> Float member

B = Data.define(:flag)
bb = B.new(flag: false)
mix = [true, 1]                   # heterogeneous [Bool, Int] -> poly element
p bb.with(flag: mix[0]).flag      # poly -> Bool member
