# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


puts (1..10) === 5      # true
puts (1..10) === 1      # true
puts (1..10) === 10     # true
puts (1..10) === 0      # false
puts (1..10) === 11     # false
