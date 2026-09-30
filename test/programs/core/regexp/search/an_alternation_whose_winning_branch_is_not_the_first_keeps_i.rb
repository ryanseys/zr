# An alternation whose winning branch is not the first one keeps its capture,
# and the other groups are nil.
p(/(\d)|(x)/.match("1").captures)        # ["1", nil]
p(/(a)|(b)|(c)/.match("b").captures)     # [nil, "b", nil]
p(/(a)|(b)|(c)/.match("c").captures)     # [nil, nil, "c"]
p(/(foo)|(bar)|(baz)/.match("baz")[3])   # "baz"
p("a1b2".scan(/(\d)|([a-z])/))           # [[nil,"a"],["1",nil],[nil,"b"],["2",nil]]

# Multiline ^ after a final newline: a trailing '\n' does not start a new
# line, so ^ must not match at end-of-string.
p("a\n".scan(/^/).size)                  # 1
p("a\nb\n".scan(/^/).size)               # 2
p(/^$/.match?("a\n"))                    # false
p("x\n".match?(/x$/))                    # true  ($ still matches before \n)
p("a\nb".scan(/^./))                     # ["a", "b"]
