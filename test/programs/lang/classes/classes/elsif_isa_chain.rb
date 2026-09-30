# An `if/elsif/else` chain with `is_a?(Class)` checks in the elsif
# branch, on a receiver of unknown type.
#
# All arms below return the same string, so the example checks only
# that the program compiles and runs.

class A
end

class B
end

def normalize(value)
  if value.is_a?(A)
    "ok"
  elsif value.is_a?(B)
    "ok"
  else
    "ok"
  end
end

puts normalize(A.new)              # ok
puts normalize(B.new)              # ok
puts normalize(42)                 # ok

# Same shape but as the method's tail-position return.
def classify(value)
  if value.is_a?(A)
    1
  elsif value.is_a?(B)
    1
  else
    1
  end
end

puts classify(A.new)               # 1
puts classify(B.new)               # 1
puts classify(99)                  # 1
