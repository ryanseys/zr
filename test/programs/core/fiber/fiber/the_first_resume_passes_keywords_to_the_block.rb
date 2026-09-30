p Fiber.new { |k:| k }.resume(k: 3)
p Fiber.new { |*a, **kw| [a, kw] }.resume(1, k: 2)
p Fiber.new { |**kw| kw }.resume({a: 1})
f = Fiber.new { |x| Fiber.yield(x) }
p f.resume(1), f.resume(k: 2)
