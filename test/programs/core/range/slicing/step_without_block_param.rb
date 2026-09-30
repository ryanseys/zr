# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


# `Integer#step` with a do-block that omits its parameter used a
# synthesized `_i` index that wasn't declared. Two paramless `step`
# blocks in the same function also redefined it.
sum_step = 0
1.step(10, 1) do
  sum_step += 1
end
1.step(5, 1) do
  sum_step += 10
end
1.step(5, 1) do
  sum_step += 100
end
puts sum_step
