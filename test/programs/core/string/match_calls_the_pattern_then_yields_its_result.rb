# String#match and Symbol#match call the pattern's match with no block,
# then yield what it returns when that is not nil.
o = Regexp.new("foo")
def o.match(x, y, z) = x + y + z
x = nil
p "foo".match(o, "bar", "baz") { |y| x = y }, x
y = nil
p :foo.match(o, "bar", "baz") { |z| y = z }, y
p "foobar".match(/bar/) { |m| m[0].upcase }, "a".match(/z/) { 1 }
