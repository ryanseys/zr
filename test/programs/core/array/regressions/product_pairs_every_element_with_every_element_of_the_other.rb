# Array#product with a single array argument of a different element type
# gives [recv_elem, arg_elem] pairs of mixed types. Two Integer arrays
# give pairs of Integers.
p [1, 2].product(["a", "b"])
p [1, 2, 3].product(["x"])
p ["a", "b"].product([1, 2])
p [1, 2].product([3, 4])
p [1.5, 2.5].product([1, 2])
