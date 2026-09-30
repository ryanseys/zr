a = [1, 2, 3]
r = []
a.reverse_each { |c| r << c; a.clear }
p r
a = [1, 2, 3, 4]
r = []
p a.rindex { |c| r << c; a.pop; false }, r
a = [1, 2, 3, 4]
a.fill { |i| a.pop; i }
p a
a = [1, 2, 3]
r = []
a.combination(2) { |c| r << c; a.clear }
p r
a = [1, 2, 3]
r = []
a.permutation(2) { |c| r << c; a.clear }
p r.size
