# `[*0..n]` and `[*arr]` are array literals with a splat element.
# The splat spreads all the values, not only the first one.
# optcarrot builds its dummy palette this way.

a = [*0..5]
puts a.length
puts a[0]
puts a[3]
puts a[5]

b = [*0...4]
puts b.length
puts b[0]
puts b[3]

src = [10, 20, 30]
c = [*src]
puts c.length
puts c[0]
puts c[2]
