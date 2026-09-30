# Array#dig walks through nested arrays of mixed element types with
# Integer keys, and gives the leaf value.

p [[1, [2, "3"]]].dig(0, 1, 1) == "3"   # true (string leaf)
p [[1, [2, "3"]]].dig(0, 0) == 1        # true (int leaf)
p [[1, [2, "3"]]].dig(0, 1, 0) == 2     # true
p [[1, [2, "3"]]].dig(0, 1, 5).nil?     # true (OOB at the last step)
