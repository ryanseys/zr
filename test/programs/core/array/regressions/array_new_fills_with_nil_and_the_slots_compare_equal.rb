# `Array.new(n, nil)` -- the fill value is the nil singleton, so
# MRI fills each slot with `nil` and `.inspect` prints
# "[nil, nil, ...]", not "[0, 0, 0]". `[i].nil?` is true for
# each slot.

ary = Array.new(3, nil)
puts ary.inspect
puts ary[0].nil?
puts ary[1].nil?
puts ary[2].nil?
puts ary.length
