# `s.split` with no arg or a nil arg splits on runs of whitespace and
# drops leading and trailing whitespace.
p "1 2 3".split
p "  leading  trailing  ".split
p "a\tb\nc".split          # mixed whitespace
p "".split                  # empty
p "abc".split(nil)          # explicit nil arg -> same as no-arg
p "a,b,c".split(",")        # non-whitespace sep
