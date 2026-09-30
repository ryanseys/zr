# Enumerator ops: chained each_with_index, +, next_values/peek_values, product
e = [10, 20].each.each_with_index
e.each { |x, i| p [x, i] }
a = [1, 2].each; b = [3, 4].each
p((a + b).to_a)
c = [1, 2].each
p(c.next_values)
p(c.peek_values)
p(Enumerator.product([1, 2], [3, 4]).to_a)
p(Enumerator.product([1, 2], [3], [4, 5]).to_a)     # 3 args
