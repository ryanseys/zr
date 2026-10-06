# `[1,2,3,4].reduce(:*)`: the symbol-arg form of reduce and inject
# with binary arithmetic and bitwise ops on an Integer array.
p [1, 2, 3, 4].reduce(:*)    # 24
p [1, 2, 3, 4].reduce(:+)    # 10
p [10, 1, 2].reduce(:-)      # 7
p [5, 3].inject(:%)          # 2
p [12, 10].inject(:&)        # 8
p [5, 3].inject(:|)          # 7
p [5, 3].inject(:^)          # 6
p [42].reduce(:+)            # 42 (single-element)
p [].reduce(:+)              # nil (empty seedless fold, matching CRuby)
