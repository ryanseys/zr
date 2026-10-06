# The combined container-read shapes coexist in one program. With Set
# required, a map! call on a value read from a container still changes
# the Array, and Set's each still works.
require 'set'
m = [[1, 2], [3, 4]]; m[1].map! { |x| x * 10 }; p m
h = { a: Set.new([1, 2, 3]) }
p h[:a].map { |x| x }
s2 = Set.new([1, 2])
hs = { b: s2 }
hs[:b].map! { |x| x + 5 }
p s2.to_a.sort
