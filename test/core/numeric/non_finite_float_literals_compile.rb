# `1e400` overflows to Infinity at parse time. Infinity has no finite
# float LITERAL to emit, so codegen must emit the constant another way
# instead -- the value is perfectly ordinary Ruby.

big = 1e400
p big
p(-1e400)
p big.infinite?
p (big - big).nan?
p [1e400, -1e400].max
__END__
Infinity
-Infinity
1
true
Infinity
