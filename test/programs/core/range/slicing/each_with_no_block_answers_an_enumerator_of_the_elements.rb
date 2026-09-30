# Range#each without a block returns an Enumerator, and chaining on it
# works.
p((1..3).each.to_a)
p((1...4).each.to_a)
p((5..8).each.to_a.length)
