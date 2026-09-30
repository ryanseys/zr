# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Control flow inside the loop ---

# `break` exits the loop early; the accumulator captures only the
# values seen before the break.
early = 0
(1..100).each { |i| break if i > 5; early = early + i }
puts early

# `next` skips the body for the current iteration; even values
# contribute, odd values are skipped.
even_sum = 0
(1..10).each { |i| next if i % 2 != 0; even_sum = even_sum + i }
puts even_sum

