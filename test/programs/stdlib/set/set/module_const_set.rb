# Module#const_set with a literal name re-assigns the constant, and Ruby
# warns that the constant is already initialized.

class Box; X = 1; S = "a"; F = 1.5; end
p Box.const_set(:X, 99)     # returns the value, as CRuby does
p Box::X
p Box.const_set(:S, "zz")
p Box::S
p Box.const_set(:F, 2.5)
p Box::F
Y = 10
Object.const_set(:Y, 20)
p Y
p Box.const_get(:X)         # const_get sees the store
p Box.const_set("X", 7)     # a String name works like a Symbol one
p Box::X
