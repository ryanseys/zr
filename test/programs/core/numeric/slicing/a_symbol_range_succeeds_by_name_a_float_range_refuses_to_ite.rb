# Symbol range iterates by name succession.
p (:a..:e).to_a
# Float range: O(1) min/max, drift-free step, float bsearch, and each
# raises (can't iterate a float range).
p (1.0..3.0).min
p (1.0..3.0).max
p (1.0..3.0).step(0.5).to_a
p (0.0..10.0).bsearch { |x| x >= 3.5 }
p(begin; (1.0..3.0).to_a; rescue => e; e.message; end)
# Negative integer step walks a descending range.
p (10..2).step(-2).to_a
# downto/upto beyond i64 iterate as BigInt, and .size is exact.
big = 2 ** 100
p big.downto(big - 2).to_a
p big.downto(big - 2).size
# downto with a Float limit yields integers.
p 5.downto(2.0).to_a
# C99 hex-float strings.
p Float("0x1p4")
p Float("0xa")
