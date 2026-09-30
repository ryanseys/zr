# Multi-assignment used as an expression value whose RHS is a call
# that returns an Array (as in `gets.split.map(&:to_i)`), followed
# by an outer subscript / comparison. The value of the assignment
# is the Array that the call returns.

def two_ints; [10, 20]; end
def three; [7, 8, 9]; end

# T1: call-returning-array RHS, value-of-expression form
result = (x, y = two_ints)
p x
p y
p result

# T2: subscript chain on the value
first = (p1, p2, p3 = three)[0]
p p1
p p2
p p3
p first

# T3: subscript chain on the value with comparison
def pair; [3, 4]; end
flag = (a, b = pair)[0] == 3
p a
p b
p flag
