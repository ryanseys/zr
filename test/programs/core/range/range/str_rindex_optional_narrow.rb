# `slash = p.rindex("/")` followed by a nil-check ternary:
#
#   tail = slash == nil ? p : p[(slash + 1)..(p.length - 1)]
#
# With a plain String argument, `String#rindex` answers an Integer
# or nil, as `String#index` does. After the nil check, `slash` is
# an Integer, so `slash + 1` works as a range start.

p = "abc/def"
slash = p.rindex("/")
tail = slash == nil ? p : p[(slash + 1)..(p.length - 1)]
puts tail

# not-found case
p2 = "no_slash_here"
slash2 = p2.rindex("/")
tail2 = slash2 == nil ? p2 : p2[(slash2 + 1)..(p2.length - 1)]
puts tail2

# multiple separators — rindex finds the last
p3 = "a/b/c/d"
puts p3.rindex("/").inspect
slash3 = p3.rindex("/")
puts slash3 == nil ? "none" : p3[(slash3 + 1)..(p3.length - 1)]

# zero-position match
puts "/foo".rindex("/")
