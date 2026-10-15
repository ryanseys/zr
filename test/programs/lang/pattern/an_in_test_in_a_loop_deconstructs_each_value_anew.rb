# `value in pattern` clears its deconstruct caches before each test, as
# case/in does, so a loop that runs it again in the same scope (`while`,
# `for`, `loop` in a method) reads each new value, not the last one's.
values = [nil, [7, 8, 9], [8], [1, 2], { k: [8] }, { k: [1] }]
for value in values
  p [(value in [*, 8, *]), (value in { k: [*, 8, *] }), (value in [_, *])]
end

i = 0
while i < values.size
  value = values[i]
  p [(value in [*, 8, *]), (value in { k: [8] })]
  i += 1
end

class Pair
  def initialize(*parts) = @parts = parts
  def deconstruct = (print "d"; @parts)
end
for pair in [Pair.new(1, 8), Pair.new(2, 3)]
  p [(pair in [_, 8]), (pair in [*, 3, *])]
end
