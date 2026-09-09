a = [1, [2, :x], "s", nil]
p a, a[1], a[-1], a[9], a.size, a.first, a.last
a << 5
a[6] = 7
p a, a.pop, a.length, a.empty?, [] == [], [1, 2] == [1, 2], [1] == [2]
x = p 1, 2
p x
p [1, 2][:a]
