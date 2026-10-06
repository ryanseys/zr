# Scalar int RHS to multi-assign: `a, b = 1`. CRuby treats the
# scalar as `[scalar]`, so the first target gets it and the extra
# targets are nil.
a, b = 1
puts a
puts b

e, f, g = 42
puts e
puts f
puts g
