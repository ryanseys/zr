# `"#{stmt1; stmt2; ...; stmtN}"` evaluates every statement in source
# order (for side effects) and uses the LAST statement's value in the
# string.

y = 0
s = "#{y = 10; y = 20; y}"
puts s
puts y

# Side effect persists outside the interpolation.
counter = 0
"#{counter += 1; counter += 1; counter += 1}"
puts counter
