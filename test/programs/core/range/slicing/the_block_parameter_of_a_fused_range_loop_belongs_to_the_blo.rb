# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Block-param scoping ---

# Block param doesn't leak when its name is distinct from outer
# locals.
outer_v = 42
(1..5).each { |inner| outer_v = outer_v + inner }
puts outer_v

