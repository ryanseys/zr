p [1, 2, 3].combination(2).to_a
p [1, 2, 3].combination(0).to_a
p [1, 2, 3].combination(4).to_a
p [1, 2, 3].permutation(2).to_a
p [1, 2].permutation.to_a
r = []
[1, 2, 3].combination(2) { |c| r << c }
p r
p [1, 2, 3].each_index.to_a
p [1, 2, 3, 4].bsearch { |x| x >= 3 }
p [1, 2, 3, 4].bsearch { |x| x >= 9 }
p [1, 2, 3, 4].bsearch_index { |x| x >= 3 }
