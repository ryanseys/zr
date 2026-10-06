# `expr rescue fallback` as an rvalue — the receiving variable gets
# the value of the arm that ran.
#
# Note: Ruby's `=` has higher precedence than the rescue modifier,
# so `a = "x" rescue "y"` parses as `(a = "x") rescue "y"` — the
# RescueModifierNode wraps the assignment, not the rvalue. To use
# the rescue modifier as an rvalue, the program puts it in parentheses.

# Same-type branches: string=string. Trivial baseline.
a = ("ok" rescue "fallback")
puts a

# Mismatched branches: main is `raise` (it never returns), fallback
# is a String. The result is the String.
b = (raise "boom" rescue "default")
puts b

# Same-type int. Endless method shape stays unchanged.
def parse_int(s) = Integer(s) rescue 0
puts parse_int("42")
puts parse_int("abc")
