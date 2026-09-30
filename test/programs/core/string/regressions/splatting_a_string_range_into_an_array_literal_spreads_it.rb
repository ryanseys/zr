# Splatting a string range into an array literal expands it into an
# array of Strings.
p [*"a".."e"]
p [*"a"..."d"]        # exclusive range drops the endpoint
p [*"x".."z", "!"]    # splat-first, then a trailing literal
p [*" ".."&"]         # the printable-ASCII idiom from the bug report
