# `Proc#parameters` reports the names the PROGRAM wrote, never names that the
# compiler makes.
#
# A block parameter can have the same name as an outer local. Each kind
# (positional, rest, keyword, keyword-rest and block) still reports the
# source name, and the name is never empty.
#
# The implicit rest that a trailing comma makes (`|a,|`) is not a parameter
# that Ruby reports.
p(->((a, b)) {}.parameters)
p(proc { |a, *b| }.parameters)
p(->(a, b = 1, *c, d:, e: 2, **f, &g) {}.parameters)
p(proc { |a, b = 1, *c, d:, e: 2, **f, &g| }.parameters)
a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; g = 7
p(proc { |a, b = 1, *c, d:, e: 2, **f, &g| }.parameters)
p([a, b, c, d, e, f, g])
p(lambda { |x, (y, z)| }.parameters)
p(proc { |*| }.parameters)
p(proc { |a, | }.parameters)
p(proc { }.parameters)
