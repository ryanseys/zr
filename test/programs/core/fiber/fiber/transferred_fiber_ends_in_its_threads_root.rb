# A fiber that ends after a transfer goes back to its thread's own root
# fiber, and Fiber#raise transfers to a fiber that transferred away.
root = Fiber.current
log = []
a = Fiber.new(blocking: false) { log << :a1; root.transfer; log << :a2 }
a.transfer
log << :back
a.transfer
log << :done
p log
t = Thread.new do
  r = Fiber.current
  b = Fiber.new(blocking: false) { log << :b1; r.transfer; log << :b2 }
  b.transfer
  log << :tback
  b.transfer
  log << :tdone
end
t.join
p log
r, w = IO.pipe
t2 = Thread.new { IO.select([r], [], [], 0.01) }
p t2.value
root = Fiber.current
f = Fiber.new { begin; root.transfer; rescue => e; p [:rescued, e.message]; end; :ended }
f.transfer
p f.raise("boom")
