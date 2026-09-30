a = [1, 2, 3]
n = 0
a.cycle { n += 1; a.clear }
p n
a = [1, 2, 3]
r = []
a.cycle(5) { |x| r << x; a.shift if r.size == 2 }
p r
p [1, 2].cycle(-1) { raise "never" }
