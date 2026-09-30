# Integer array slicing: a[range] and a[start, len].
# Both forms give a new array, not a single element.

a = [10, 20, 30, 40, 50]

# Range form
b = a[1..3]
puts b.length      # 3
puts b[0]          # 20
puts b[1]          # 30
puts b[2]          # 40

# (start, len) form
c = a[1, 2]
puts c.length      # 2
puts c[0]          # 20
puts c[1]          # 30

# Negative start (counts from end)
d = a[-2, 2]
puts d.length      # 2
puts d[0]          # 40
puts d[1]          # 50

# len exceeds remaining: clamped
f = a[2, 100]
puts f.length      # 3
puts f[0]          # 30
puts f[2]          # 50

# Range to last index
g = a[2..4]
puts g.length      # 3
puts g[0]          # 30
puts g[2]          # 50

# Bare a[i] still works as scalar get
puts a[0]          # 10
puts a[-1]         # 50

# The result is an Integer array too
puts a[1..3].sum   # 90
