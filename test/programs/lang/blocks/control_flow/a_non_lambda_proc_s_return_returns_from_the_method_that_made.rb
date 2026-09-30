# A non-lambda proc's `return` returns from the method that created the proc
# (CRuby non-local return); a lambda's `return` is local to the lambda.
def m
  proc { return 30 }.call
  40
end
p m

