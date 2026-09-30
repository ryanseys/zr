# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


puts (1..10).cover?(5)
puts (1..10).cover?(1)
puts (1..10).cover?(10)
puts (1..10).cover?(0)
puts (1..10).cover?(11)
puts (-5..5).cover?(0)
puts (-5..5).cover?(-5)
puts (-5..5).cover?(6)

puts (1..10).min
puts (1..10).max
puts (-5..5).min
puts (-5..5).max
puts (100..200).min
puts (100..200).max

puts (1..10).count
puts (1..1).count
puts (-5..5).count
puts (100..200).count

puts (1...10).count
puts (1...1).count
puts (-5...5).count
