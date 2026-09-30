# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


puts (0..3).map { |i| i * 10 }.length      # 4
puts (0..3).map { |i| i * 10 }[2]          # 20
puts (0...3).map { |i| i }.length          # 3
puts (0...3).map { |i| i }[2]              # 2
puts ((1..3).map { |i| "x#{i}" }.join(","))   # x1,x2,x3
puts ((0...3).map { |i| i * 0.5 }.length)     # 3
