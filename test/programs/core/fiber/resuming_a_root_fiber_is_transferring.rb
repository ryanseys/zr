# A root fiber has started and is not in Fiber.yield, so a resume of it
# says it is transferring, before the check across threads.
def try
  yield
rescue FiberError => e
  e.message
end

root = Fiber.current
p try { root.resume }
p Thread.new { try { root.resume } }.value
p Thread.new { Fiber.new { try { root.resume } }.resume }.value
p Thread.new { try { Fiber.current.resume } }.value
f = Fiber.new { Fiber.yield 1; 2 }
p f.resume, f.resume
