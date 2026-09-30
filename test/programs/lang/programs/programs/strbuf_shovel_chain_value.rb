# A value-position << chain over a buffer-promoted string local must land
# every link in the base: `r = (u << "2" << "3")` keeps both appends in u,
# not only the first.

s = "ab"
s << "c" << "d"
p s

t = "x"
t << "y" << "z" << "w"
p t

u = "1"
r = (u << "2" << "3")
p u
p r

v = "a"
q = (v << "b" << "c" << "d")
v << "e"
p v
p q
