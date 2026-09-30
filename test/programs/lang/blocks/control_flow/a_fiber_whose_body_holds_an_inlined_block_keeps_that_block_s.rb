# A fiber whose body contains an inlined block: the block params/locals are
# collected for the fiber function (parallels the proc collection fix).
fib = Fiber.new do
  total = 0
  [1, 2, 3].each { |x| total += x }
  Fiber.yield total
end
p fib.resume
