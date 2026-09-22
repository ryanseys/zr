# shareable_constant_value: literal
# A constant of literals alone is built frozen with no send; a Range is
# a literal as the value and not as an element (compile.c's
# static_literal_node_p); anything else is made shareable at run time.
SPAN = ("a".."c")
DEEP = [1, "s", { k: [2, :z] }, __FILE__]
WITH_RANGE = [(1..2)]
HELD = [1, "s".b.freeze]
