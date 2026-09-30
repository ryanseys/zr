# `enum_cycle_size`: endlessly where no round was named, none where
# the rounds are none or fewer, and otherwise the count times the
# rounds. A Struct reaches Enumerable's own cycle and inspects the
# same way twice, which a plain object does not.
Trio = Struct.new(:a, :b, :c)
t = Trio.new(1, 2, 3)

p t.cycle.size
p t.cycle(2).size
p t.cycle(0).size
p t.cycle(-1).size
p t.map.size
