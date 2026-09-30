# `a[1..-2]` gives [a[1], a[2], a[3]] for a 5-element array: a negative
# end counts from the end of the collection.
#
# Test covers four receiver shapes: an Integer array, a Float array,
# a String array, and a String. Exclusive (`...`) and inclusive (`..`) forms both
# exercise negative endpoints.

a = [0, 1, 2, 3, 4]
p a[1..-2]   # inclusive: [1, 2, 3]
p a[1...-1]  # exclusive: [1, 2, 3]
p a[-3..-1]  # both negative: [2, 3, 4]
p a[0..-1]   # whole array: [0, 1, 2, 3, 4]
p a[2..-3]   # single element (-3 -> 2, so a[2..2]): [2]
p a[-4..-2]  # negative start, negative end: [1, 2, 3]

f = [0.5, 1.5, 2.5, 3.5]
p f[1..-2]   # [1.5, 2.5]

s_arr = ["a", "b", "c", "d", "e"]
p s_arr[1..-2]   # ["b", "c", "d"]

s = "hello"
p s[1..-2]   # "ell"
p s[1...-1]  # "ell"
p s[-3..-1]  # "llo"
p s[-4..-2]  # negative start + end: "ell"
