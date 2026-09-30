a = [1.5, 2.5, 3.5, 4.5, 5.5]
b = a[1..3]
puts b.length    # 3
puts b[0]        # 2.5
puts b[1]        # 3.5
puts b[2]        # 4.5
c = a[1, 2]
puts c.length    # 2
puts c[0]        # 2.5
puts c[1]        # 3.5
d = a[-2, 2]
puts d.length    # 2
puts d[0]        # 4.5
puts d[1]        # 5.5
e = a[2, 100]
puts e.length    # 3 (clamped)
puts e[0]        # 3.5
puts e[2]        # 5.5
puts a[0]        # 1.5
puts a[-1]       # 5.5
puts a[1..3].sum # 10.5
