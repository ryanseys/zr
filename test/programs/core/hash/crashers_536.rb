# Three edge cases:
#
# 1. `[].sample` on an empty Array answers nil.
#
# 2. `[1,2,3,2].union` (no args) answers the elements without
#    duplicates.
#
# 3. `{ 0 => false, a: 1 }` has an Integer key and a Symbol key
#    in one literal. Both keys work.

# Empty Array#sample returns nil, matching CRuby.
puts [].sample.inspect

# No-args Array#union reduces to dedup.
puts [1, 2, 3, 2].union.inspect

# Mixed-key hash literal.
h = { 0 => false, a: 1 }
puts h.size
puts h[:a]
