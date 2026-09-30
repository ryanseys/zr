# Three-step `arr.each_cons(n).with_index(off).map { ... }` chain. CRuby
# returns an Enumerator from each_cons, then another from
# with_index, and consumes both at the terminal .map. The index
# starts at `off` (default 0) and goes up by one after each pair.
#
# Block param shapes:
#   |pair, i|       -- pair is the sub-array, i is the Integer index
#   |(a, b), i|     -- nested destructure of pair into individual
#                      window elements, trailing i as Integer index

# T1: |pair, i| with explicit offset
p [10, 20, 30, 40].each_cons(2).with_index(1).map { |pair, i| pair[0] + pair[1] + i }

# T2: |(a, b), i| destructure, explicit offset
p [10, 20, 30, 40].each_cons(2).with_index(1).map { |(a, b), i| b - a + i }

# T3: default offset (0)
p [1, 2, 3].each_cons(2).with_index.map { |pair, i| pair[1] - pair[0] + i }

# T4: block returns array -> result is an Array of Arrays
p [1, 2, 3, 4].each_cons(2).with_index(1).map { |(a, b), i| [b - a, i] }
