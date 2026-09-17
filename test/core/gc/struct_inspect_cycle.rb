# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
# 
# A Struct holding itself, which is what the golden inspects.
# At exit: cycle leak: 1 objects (S x1)
S = Struct.new(:x)
s = S.new(nil)
s.x = s
p s
__END__
#<struct S x=#<struct S:...>>
