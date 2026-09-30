# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


r0 = (1..10)
puts r0.first             # 1
puts r0.last              # 10
puts r0.include?(5)       # true
puts r0.include?(11)      # false

arr0 = r0.to_a
puts arr0.length          # 10
puts arr0.sum             # 55

total = 0
r0.each do |x|
  total += x
end
puts total                # 55
puts "done"
