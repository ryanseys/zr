# Fiber.new(&pr) and an Enumerator's yielder pass on only the keywords given,
# so a lone Array still spreads over a block that takes several values.
e = Enumerator.new { |y| y.yield([1, 2]); y << [3, 4]; y.yield([5, 6], k: 1) }
e.each { |a, b| p [a, b] }
e2 = Enumerator.new { |y| [[1, 2]].each(&y) }
e2.each { |a, b| p [a, b] }
opt = proc { |a, b = 5| [a, b] }
p Fiber.new(&opt).resume([7, 8])
k = proc { |a, b = 5, k: 0| [a, b, k] }
p Fiber.new(&k).resume([7, 8], k: 2)
