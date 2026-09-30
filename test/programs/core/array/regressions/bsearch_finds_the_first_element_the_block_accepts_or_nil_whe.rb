# Array#bsearch (find-minimum mode) on a sorted typed array: returns the
# first element for which the block is truthy, or nil when none is.
p [1, 3, 5, 7, 9].bsearch { |x| x >= 5 }
p [1, 3, 5, 7, 9].bsearch { |x| x >= 100 }
p [1, 3, 5, 7, 9].bsearch { |x| x >= 1 }
p [2, 4, 6, 8].bsearch { |x| x >= 7 }
p ["a", "b", "c", "d"].bsearch { |s| s >= "c" }
p ["a", "b", "c", "d"].bsearch { |s| s >= "z" }
