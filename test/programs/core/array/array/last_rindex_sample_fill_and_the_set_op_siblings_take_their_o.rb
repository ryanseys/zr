# The builtins accept the optional-`n` and variadic forms that Ruby
# accepts: `last(n)`, `sample(n)`,
# the block form of `rindex`, the fill span forms, and the variadic
# set-op siblings `union`/`intersection`/`difference` (distinct from the
# binary `|`/`&`/`-`). All oracle-verified against ruby 4.0.7.

p [1, 2, 3].last(2)
p [1, 2, 3].last(0)
p [1, 2, 3].last(5)
p [1, 2, 3, 2].rindex { |x| x < 3 }
p [1, 2, 3, 2].rindex(2)
p [1, 2, 3].union
p [1, 2, 3].union([2, 3], [4])
p [1, 2, 3, 4].intersection([2, 3, 4], [3, 4, 5])
p [1, 2, 3].difference([2], [4])
p [1, 1, 2].difference([2])
a = [0, 0, 0]; a.fill(9); p a
a = [0, 0, 0]; a.fill(9, 1, 1); p a
a = [1, 2, 3]; a.fill(9, 1, 5); p a
a = [1, 2, 3]; a.fill { |i| i }; p a
a = [1, 2, 3, 4, 5]; a.fill(-2) { |i| i * 10 }; p a
p [1, 2, 3].sample(2).length
p [1, 2, 3].sample(5).sort
