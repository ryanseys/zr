# `[1, nil, 2].compact` starts from an array with mixed element types.
# It compares equal to a literal like `[1, 2]` element by element, in
# both operand orders.

p [1, nil, 2].compact                          #=> [1, 2]
p([1, nil, 2].compact == [1, 2])               #=> true
p([1, nil, 2].compact == [1, 3])               #=> false
p([1, 2] == [1, nil, 2].compact)               #=> true  (reverse order)
p(["a", nil, "b"].compact == ["a", "b"])       #=> true
p([1.0, nil, 2.0].compact == [1.0, 2.0])       #=> true
p([1, nil].compact == [1])                     #=> true
p([1, nil, 2].compact != [1, 2])               #=> false
p([1, nil, 2].compact != [9])                  #=> true
puts "done"
