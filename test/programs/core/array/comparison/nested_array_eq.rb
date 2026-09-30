# Array#== on an array of arrays/objects compares deeply, element by
# element, so `[[1]] == [[1]]` is true.

p([[1]] == [[1]])                         #=> true
p([[1, 2], [3]] == [[1, 2], [3]])         #=> true
p([[1]] == [[2]])                         #=> false
p([[1], [2]] == [[1]])                    #=> false (length)
p([["a"], ["b"]] == [["a"], ["b"]])       #=> true
p([["a"]] == [["b"]])                     #=> false
p([[1.0]] == [[1.0]])                     #=> true
p([[1]] != [[2]])                         #=> true
p([[1]] != [[1]])                         #=> false

x = [[1, 2, 3]]
y = [[1, 2, 3]]
p(x == y)                                 #=> true
x[0] << 4
p(x == y)                                 #=> false

puts "done"
