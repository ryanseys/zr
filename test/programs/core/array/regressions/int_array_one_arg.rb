# Enumerable#one?(x) — true iff exactly one element equals x.
# This is the argument form, with no block.
puts [1,2,3].one?(2)
puts [1,2,3].one?(99)
puts [1,2,2].one?(2)
puts [].one?(1)
puts [5].one?(5)
