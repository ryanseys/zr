# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Non-trivial bounds ---

# Non-literal bounds (variable-bounded range) — falls back to the
# generic sp_Range path. Behaviour must still match.
lo = 2
hi = 6
var_sum = 0
(lo..hi).each { |x| var_sum = var_sum + x }
puts var_sum

# Parens-wrapped range — `((1..5))` is a ParenthesesNode wrapping a
# RangeNode. The fusion recognizer must unwrap parens before
# deciding whether to inline.
p_sum = 0
((1..5)).each { |i| p_sum = p_sum + i }
puts p_sum

