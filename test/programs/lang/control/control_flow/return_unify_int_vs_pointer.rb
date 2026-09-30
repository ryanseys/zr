# A method's explicit `return X` and its implicit final-expression
# return have different types (here an Integer param on the early
# return and a Hash literal at the end). The method returns each
# value as it is, so the caller gets an Integer or a Hash.

def f(value)
  return value if value < 0
  {"k" => "v"}
end

# The early-return path returns the int parameter.
r1 = f(-1)
puts r1.is_a?(Integer)
puts r1

# The implicit-return path returns the hash literal.
r2 = f(5)
puts r2.is_a?(Hash)
puts r2["k"]
