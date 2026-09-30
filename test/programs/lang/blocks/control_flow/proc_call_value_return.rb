# `lambda {}` / `proc {}` (method-call form) record their block's return
# type, so `.call` gives a value of that type, not an Integer.
f = lambda { "hello" }
puts f.call

g = proc { "world" }
puts g.call

# An Array return value.
h = lambda { [1, 2, 3] }
p h.call

# A rescue-bound exception value flows out through the same path.
r = lambda { begin; raise "boom"; rescue => e; "msg:#{e.message}"; end }
puts r.call

# An Integer return value.
n = proc { 42 }
puts n.call
