# `Array.new(n)` (single arg, no fill value, no block) is CRuby
# shorthand for `Array.new(n, nil)`: an array of n nils, NOT an
# empty array.
puts Array.new(3).length         # 3
puts Array.new(3).inspect        # [nil, nil, nil]
puts Array.new(3)[0].nil?        # true
puts Array.new(0).length         # 0
puts Array.new(5).length         # 5
