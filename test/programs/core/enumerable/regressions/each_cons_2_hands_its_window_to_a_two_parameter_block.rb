# each_cons(2).map { |a, b| ... } over an Integer array: the window's
# elements bind to the two block params, one element each.
codes = (0...8).map { |n| n * 2 }
d = codes.each_cons(2).map { |a, b| a + b }
w = codes.last
p d
p w
p [1.0, 2.0, 3.0].each_cons(2).map { |a, b| a * b }
