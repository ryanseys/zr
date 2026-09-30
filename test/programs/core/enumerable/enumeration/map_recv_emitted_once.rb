# `n, m = gets.split.map &:to_i` evaluates the receiver of `map`
# once. For `gets` (and any other side-effecting call), a second
# evaluation would consume two lines of stdin per iteration.
#
# The receiver must also stay alive for the GC while `map` runs,
# also when it is an array literal like `[10,20,30,40].map { ... }`.

# Counter-style verifies side-effect-once. Each call to `next!`
# bumps the counter; the test asserts the counter only moves by
# the expected amount across the multi-assign.
$counter = 0
def next!
  $counter += 1
  $counter.to_s + " " + ($counter + 100).to_s
end

# Multi-assign over a side-effecting recv. `next!` returns the
# string; the chain splits/maps it.
a, b = next!.split.map { |x| x.to_i }
puts a
puts b
puts $counter  # 1 (called once)

# Nested map with array-literal recv (the GC-rooting concern --
# the recv temp is the literal, no other root holds it).
TBL = [10, 20, 30, 40].map { |a| (0...8).map { |j| a + j } }
puts TBL.length         # 4
puts TBL[0].length      # 8
puts TBL[0][0]          # 10
puts TBL[3][7]          # 47
