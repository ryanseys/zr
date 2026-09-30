# A compound assignment on a plain, non-class constant must dispatch
# correctly: `MAX += 1` (desugared to `MAX.+(1)`, where `MAX` is a
# plain `Integer` constant, not a class) must read and write its
# actual value, the same as every other compound-assignment operator.

MAX = 100
MAX += 1
puts MAX
MAX -= 50
puts MAX
