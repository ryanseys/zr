# A Hash literal whose keys are the consecutive non-negative
# integers 0..N-1, like
#
#   {0 => [...], 1 => [...]}
#
# A `[]` lookup returns the value for the key, and chained calls on
# the value work.

TBL = {0 => [3, 7, 2, 6], 1 => [4, 0, 5, 1]}
puts TBL[0].length      # 4
puts TBL[1][2]          # 5
