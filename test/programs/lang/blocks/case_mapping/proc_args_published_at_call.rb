# Two Proc calls in one expression each get their own arguments. A composed
# Proc passes the result of its first stage to its second stage.
strip = ->(s) { s.strip }
down  = ->(s) { s.downcase }
fwd = strip >> down
p fwd.call("  AB  ")
p(fwd.call("  AB  ") == fwd.call("  AB  "))

# two DIFFERENT arguments in one expression: each call has to see its own
add = ->(a, b) { a + b }
p(add.call(1, 2) + add.call(10, 20))
p [add.call(1, 2), add.call(3, 4), add.call(5, 6)]

# a plain (uncomposed) lambda on both sides
up = ->(s) { s.upcase }
p(up.call("a") + up.call("b"))

# nested: the inner call publishes while the outer one is being built
wrap = ->(s) { "[#{s}]" }
p wrap.call(wrap.call("x"))

# three stages composed, called twice in one expression
back = down << strip
p(back.call("  CD  ") == back.call("  CD  "))
p [fwd.call("  EF  "), back.call("  GH  ")]
