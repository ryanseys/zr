# Expression shapes: multi-value return/break/next, parenthesized
# statement sequences, the fuller interpolation forms, and top-level
# instance variables.

# --- parenthesized statement sequences --------------------------------------
# `(a; b)` evaluates each in order and answers the LAST.
p((1; 2; 3))

# It introduces NO scope of its own -- a local assigned inside is still
# readable afterwards.
doubled = (n = 5; n * 2)
p doubled
p n

# Newline-separated is the same construct.
computed = (
  base = 7
  base + 1
)
p computed

# In argument and element position, and nested.
p((puts "side effect"; 42))
p [(1; 2), 3]
p((1; (2; 3)))

# A statement can be any expression, including an `if`.
p((if true then "yes" else "no" end; "after"))

# One statement in parens is just that expression.
p (5)

