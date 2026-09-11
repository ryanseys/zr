# awk-style split breaks on space and \t through \r only: a NUL stays
# inside its word, while strip takes NUL off the ends.
p "a\0b".split(" "), "a\0 b".split(" "), " a\v b\fc\r\n".split(" ")
p "\0a\0".strip, "\0 a".lstrip, "a \0".rstrip
p "x y z".split(" ", 2), " x  y ".split(" ", 2), "  x y  ".split(" ", -1)
p "one".split(" ", -1), " a b ".split(" ", 3), " a b ".split(" ", 4), "   ".split(" ", -1)
__END__
["a\u0000b"]
["a\u0000", "b"]
["a", "b", "c"]
"a"
"a"
"a"
["x", "y z"]
["x", "y "]
["x", "y", ""]
["one"]
["a", "b", ""]
["a", "b", ""]
[""]
