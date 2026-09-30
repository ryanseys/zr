# Compound index assignment on a typed array with a right-hand side of
# unknown type: `floats[i] += b[0]` where b is a mixed array. It gives
# the same result as the plain form `a[i] = a[i] + b[0]`. Also covers
# `+=` on a String array slot and `+=` on a mixed-array receiver.

# Float array: a[i] += a value of unknown type, with a literal index,
# a variable index, and inside a loop
a = Array.new(2, 0.0)
b = [1.5, "x"]
a[0] += b[0]
r = 1
a[r] += b[0]
p a                # [1.5, 1.5]
i = 0
while i < 2
  a[i] += b[0]
  i += 1
end
p a                # [3.0, 3.0]
a[0] -= b[0]
a[0] *= b[0]
a[1] /= b[0]
p a                # [2.25, 2.0]

# Integer array: a[i] op= a value of unknown type, for arithmetic and
# shifts
n = [10, 20]
m = [3, "x"]
n[0] += m[0]
n[1] -= m[0]
n[0] *= m[0]
p n                # [39, 17]
n[0] <<= m[0]
p n                # [312, 17]

# String array: a[i] += a String, and += a String of unknown type
s = ["ab", "cd"]
s[0] += "!"
t = ["ef", 1]
s[1] += t[0]
p s                # ["ab!", "cdef"]

# String array: a[i] <<= (String#<< appends) and *= (String#* repeats)
u = ["x", "y"]
u[0] <<= "z"
u[1] *= 3
p u                # ["xz", "yyy"]

# same ops when the array's element type is not known (mixing *= and
# <<= on one array does that): `*` and `<<` still act as String methods
w = ["ab", "cd"]
w[0] *= 2
w[1] <<= "!"
p w                # ["abab", "cd!"]

# mixed-array receiver: += a Float, an Integer, and a slot of unknown type
pa = [1.5, "x", 2]
pa[0] += 2.0
pa[2] += 5
pa[0] += pa[2]
p pa[0]            # 10.5
p pa[2]            # 7
