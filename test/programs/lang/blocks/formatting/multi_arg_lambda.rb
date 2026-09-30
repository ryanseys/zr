# `->(a, b) { a + b }` and longer-arity lambdas: every param is a formal
# param, and the call passes every arg.

add = ->(a, b) { a + b }
puts add.call(3, 4).to_s        # 7

mul3 = ->(a, b, c) { a * b * c }
puts mul3.call(2, 3, 5).to_s    # 30

quad = ->(a, b, c, d) { a + b + c + d }
puts quad.call(1, 2, 3, 4).to_s # 10

# 1-arg lambda.
double = ->(x) { x * 2 }
puts double.call(21).to_s       # 42

# Comparison
gt = ->(a, b) { a > b }
puts gt.call(5, 3).to_s         # true
puts gt.call(2, 9).to_s         # false
