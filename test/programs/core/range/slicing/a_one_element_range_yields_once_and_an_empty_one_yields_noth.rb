# Range#each over a literal numeric range should fuse to a tight C
# for-loop with bounds inlined. Output is identical to the unfused
# path; this test pins behavioural parity. The perf win shows up in
# the generated C — no sp_Range struct copy on the loop's hot path.

# --- Edge sizes ---

# Single-element inclusive range
hits = 0
(7..7).each { |i| hits = hits + 1 }
puts hits

# Empty exclusive range (start == end, exclusive)
empties = 0
(5...5).each { |i| empties = empties + 1 }
puts empties

# Zero-element inclusive range at the origin
zero_hits = 0
(0..0).each { |i| zero_hits = zero_hits + 1 }
puts zero_hits

# Decreasing range — start > end. CRuby yields zero times; the
# fused for-loop's `i <= hi` check is false on entry.
dec_count = 0
(10..1).each { |i| dec_count = dec_count + 1 }
puts dec_count

# Decreasing exclusive range — same zero-iteration shape.
dec_excl = 0
(10...1).each { |i| dec_excl = dec_excl + 1 }
puts dec_excl

