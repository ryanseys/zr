# Verify two expression-context constructs:
# - `(stmt1; stmt2; ...; expr)` — leading statements run for
#   side effects; the value of the parens is the last expression.
# - `local = expr` and `local OP= expr` used as expressions —
#   they assign and yield the new value of the local.

# (1) Multi-stmt parens — leading side effects must run.
x = 0
y = (x = x + 1; x = x + 1; x)
puts x      # 2
puts y      # 2

# (2) `local = expr` as the value of an outer expression.
a = 0
b = (a = 5)
puts a      # 5
puts b      # 5

# (3) `local OP= expr` as the value of an outer expression.
c = 10
d = (c += 3)
puts c      # 13
puts d      # 13
