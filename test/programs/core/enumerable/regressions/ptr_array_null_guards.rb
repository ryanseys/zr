# The full chain `each_cons(n).with_index(off).map { ... }` followed by
# `.drop.take.max[i]` gives CRuby's `3`. Each step gets the array that
# the step before it makes.

q = [100, 90, 82, 70, 65]
a = 2
b = 4
p q.each_cons(2).with_index(1).map { |(x, y), i| [x - y, i] }.drop(a - 1).take(b - a + 1).max[1]
