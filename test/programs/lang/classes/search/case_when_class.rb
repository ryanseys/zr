# `case obj when ClassConst` on a receiver that can hold values of
# different classes. Module#=== is equivalent to `arg.is_a?(recv)`,
# so each arm tests the class of the value and its ancestors.
#
# Coverage:
#   - Class match against a receiver that carries primitives.
#   - Multiple primitive class arms in one case.
#   - else clause.

def describe(v)
  case v
  when Integer
    "int"
  when String
    "string"
  when Float
    "float"
  when Symbol
    "symbol"
  else
    "other"
  end
end

puts describe(42)
puts describe("hello")
puts describe(3.14)
puts describe(:sym)
puts describe(nil)
