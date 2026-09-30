# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Basic bounds ---

# Inclusive range, accumulator
sum = 0
(1..10).each { |i| sum = sum + i }
puts sum

# Exclusive range — last value is excluded
sum_excl = 0
(1...10).each { |i| sum_excl = sum_excl + i }
puts sum_excl

# Negative bounds
neg_sum = 0
(-3..3).each { |i| neg_sum = neg_sum + i }
puts neg_sum

# Crosses zero, exclusive
zero_sum = 0
(-2...2).each { |i| zero_sum = zero_sum + i }
puts zero_sum

