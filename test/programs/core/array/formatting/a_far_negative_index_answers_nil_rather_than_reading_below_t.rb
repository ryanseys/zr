# a[-100] on a 3-element array gives nil and does not crash.
# An index far past either end reads no memory outside the array.

a = [1, 2, 3]
# These give nil.
a[-100]
a[100]
puts a[-1]
puts a[2]

sa = ["a", "b", "c"]
puts sa[-100].inspect
puts sa[100].inspect

fa = [1.0, 2.0, 3.0]
fa[-100]
fa[100]
puts fa[-1]
puts fa[1]
