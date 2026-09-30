# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Nesting ---

# Nested ranges
total = 0
(1..3).each { |i| (1..3).each { |j| total = total + i * j } }
puts total

# Triple-nested with mixed inclusive/exclusive
mixed = 0
(1..2).each { |a| (1...3).each { |b| (0..1).each { |c| mixed = mixed + a * b + c } } }
puts mixed
