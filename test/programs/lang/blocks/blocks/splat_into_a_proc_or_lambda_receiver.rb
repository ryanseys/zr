add3 = ->(a, b, c) { a + b + c }
args = [1, 2, 3]
p add3.call(*args)
p add3[*args]
p add3.(*args)
p add3.yield(*args)
prc = proc { |a, b| a * b }
p prc.call(*[4, 5])
