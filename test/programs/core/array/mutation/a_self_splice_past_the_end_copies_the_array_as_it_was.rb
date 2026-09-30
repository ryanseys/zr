b = [1, 2, 3, 4, 5, 6, 7, 8]
b[5, 0] = b
p b
c = [1, 2, 3]
c[1, 1] = c
p c
d = [1, 2, 3]
d[0..0] = d
p d
e = [1, 2]
e.concat(e, e)
p e
f = [1, 2, 3]
f.insert(1, *f)
p f
g = [1, 2, 3]
g[10, 0] = g
p g
h = [1, 2, 3]
h.replace(h)
p h
i = [1, 2, 3]
i.unshift(*i)
p i
