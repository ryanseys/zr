# `last(n)` on an endless range raises rather than trying to reach a tail that
# is not there. Range#last(n) must check for the endless range itself: an
# Enumerable `to_a` walks `each` and never ends.
#
# `first(n)` and `min` are the counterpart -- they count UP from begin, so an
# endless range answers them.
r = ((1..).last(2) rescue $!.class)
p r
p((1..).first(2))
p((1..).min)
p((1..5).last(2))
p((1..5).last)
p((1...5).last(2))
