# InterpolatedSymbolNode -- `:"foo_#{x}"`.
#
# It builds the string like InterpolatedStringNode, then interns it,
# so equal names give the same Symbol.

x = "world"
sym = :"hello_#{x}"
puts sym                # hello_world

n = 42
sym2 = :"item_#{n}"
puts sym2               # item_42

# Symbol passed through a method
def kind(s) = s.to_s
puts kind(:"prefix_#{x}")   # prefix_world
