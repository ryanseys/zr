# `[0,0,0] == %i[a a a]` must answer FALSE -- CRuby compares element
# classes too, so the Integer 0 is not equal to the Symbol :a.
# This is true even when a Symbol's internal id is 0.

p [0, 0, 0] != %i[a a a]                 # true
p [0, 0, 0] == %i[a a a]                 # false
p %i[a a a] != [0, 0, 0]                 # true

# Arrays of the same element type still compare by their elements.
p [1, 2, 3] == [1, 2, 3]                 # true
p %i[a b c] == %i[a b c]                 # true
p %i[a b c] != %i[a b]                   # true (length differs)

# An array that starts with Integers and then gets a Symbol by `<<`.
# It is equal to a literal [:foo] with the same Symbol.
a = [1]
a.shift
a << :foo
p a == [:foo]                            # true
