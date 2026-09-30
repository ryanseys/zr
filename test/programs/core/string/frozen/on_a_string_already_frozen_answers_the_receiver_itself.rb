# String#-@ on an already-frozen string returns the receiver itself.
a = "abc".freeze
p((-a).equal?(a))
c = -"xyz"
p((-c).equal?(c))
