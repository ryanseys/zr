# frozen_string_literal: true

# A `*` splat at a call site makes the argument count unknown at compile
# time, so the send hands the runtime ONE Array rather than a slot array
# and the runtime spreads it. `...` forwards the three channels the
# parameter took: the positional rest, the keywords and the block.

def report(*a, **k, &b) = [a, k, b.nil? ? nil : b.call]

list = [1, 2, 3]
p report(*list)
p report(*list, 9)
p report(0, *list)
p report(*list, x: 1)
p report(*list, **{ y: 2 })
p report(*[]) { :blocked }

p [1, 2].push(*list)
p "%s-%s" % ["a", "b"]
p [0, *list, 4]

def forward(...) = report(...)

p forward(1, 2, x: 3)
p forward(1) { :blocked }
p forward
p method(:forward).parameters
p method(:forward).arity

# A splat-expanded Hash is POSITIONAL again, not a keyword channel.
def positional(a) = a
p positional(*[{ z: 1 }])

# The splat runs ruby's `to_a` rule, so anything that answers one spreads.
p report(*(1..3))
p report(*nil)
__END__
[[1, 2, 3], {}, nil]
[[1, 2, 3, 9], {}, nil]
[[0, 1, 2, 3], {}, nil]
[[1, 2, 3], {x: 1}, nil]
[[1, 2, 3], {y: 2}, nil]
[[], {}, :blocked]
[1, 2, 1, 2, 3]
"a-b"
[0, 1, 2, 3, 4]
[[1, 2], {x: 3}, nil]
[[1], {}, :blocked]
[[], {}, nil]
[[:rest, :*], [:keyrest, :**], [:block, :&]]
-1
{z: 1}
[[1, 2, 3], {}, nil]
[[], {}, nil]
