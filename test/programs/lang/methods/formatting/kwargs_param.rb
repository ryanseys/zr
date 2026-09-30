# KeywordRestParameterNode -- def f(**kw)
#
# Declares a method that captures all keyword arguments into a single
# Symbol-keyed Hash. Other examples read kw in the body (kw[:key],
# kw.length); this test verifies the declaration alone compiles and the
# existing **nil form still works.
#
# Forwarding usage (**kw → another method's **kw slot) is exercised by
# test/forwarding_args.rb, which routes through cluster A3 + B1.

# Declaration compiles; body never reads kw, so no kwargs runtime path
# is needed. Validates that the param does not change a call that
# passes no kwargs.
def silent(a, **kw)
  a + 1
end
puts silent(2).to_s   #=> 3

# `def f(**nil)` is the explicit "rejects keyword args" form.
# Verifies the existing NoKeywordsParameterNode handling still works
# after the parser's PARAMETERS_NODE flattener gained the keyword_rest
# emission (cluster A1).
def strict(a, b, **nil)
  a + b
end
puts strict(2, 3).to_s   #=> 5
