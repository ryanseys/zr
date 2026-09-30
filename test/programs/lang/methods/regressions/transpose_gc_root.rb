# `Array#transpose` builds the result array and its inner columns.
# A collection that the next column's allocation triggers must not
# free the result array.
#
# Trigger: a transpose of a large array-of-arrays. Optcarrot's
# `(0..7).map { (0...0x10000).map {...} }.transpose` allocates
# 8 outer + 65536 × 8 inner ints in close succession.

big = (0..7).map { |a| (0..1023).map { |b| a * 1000 + b } }.transpose
puts big.length        # 1024
puts big[0].length     # 8
puts big[100][3]       # 3*1000 + 100 = 3100
puts big[1023][7]      # 7*1000 + 1023 = 8023
