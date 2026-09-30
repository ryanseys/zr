# `arr[i, n] = src` (Array#[]= with three args) replaces n
# elements of `arr` starting at index i with the elements of
# `src`. Here n is always equal to `src.length`.
#
# The second argument is a length, not the value to store.

a = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
a[2, 8] = [10, 20, 30, 40, 50, 60, 70, 80]
p a

# Float array
f = [0.0, 0.0, 0.0, 0.0]
f[1, 2] = [3.5, 4.5]
p f

# String array
s = ["", "", "", ""]
s[0, 3] = ["a", "b", "c"]
p s
