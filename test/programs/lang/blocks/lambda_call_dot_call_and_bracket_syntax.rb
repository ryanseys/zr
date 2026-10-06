add = ->(x, y) { x + y }
puts add.call(3, 4)
puts add.(3, 4)
puts add[3, 4]

square = lambda { |x| x * x }
puts square.call(5)

incr = -> (n = 1) { n + 1 }
puts incr.call
puts incr.call(10)
