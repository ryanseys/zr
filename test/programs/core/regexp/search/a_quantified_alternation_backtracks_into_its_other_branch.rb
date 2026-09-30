# A greedy `\d+` that also starts the first alternative keeps its loop:
# `/\d+|\w/` on "1b2c3" matches "1", and does not fall into the
# alternation after one digit.

p(/\d+|\w/.match("1b2c3")[0])     # "1"
p(/a+|b/.match("aaab")[0])        # "aaa"
p(/[0-9]+|z/.match("42z")[0])     # "42"
p(/\w+|\d/.match("abc")[0])       # "abc"
p(/(\d+)|(x)/.match("99").captures) # ["99", nil]

# Quantifier kinds in front of an alternation atom still work.
p(/a*|b/.match("aaa")[0])         # "aaa"
p(/a?|b/.match("a")[0])           # "a"
p(/\d{2,}|y/.match("123y")[0])    # "123"

# Plain quantifier (no alternation) and skip-past-atom jumps unaffected.
p(/\d+/.match("12ab")[0])         # "12"
p(/(ab)+c/.match("ababc")[0])     # "ababc"
p(/colou?r/.match("color")[0])    # "color"
p(/colou?r/.match("colour")[0])   # "colour"

# Lookaround (also routes through insert_inst) still works.
p(/\d+(?=px)/.match("10px")[0])   # "10"
p(/(?<=\$)\d+/.match("$50")[0])   # "50"
