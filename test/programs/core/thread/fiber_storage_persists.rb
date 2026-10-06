# Storage values persist across yield/resume cycles within the same
# fiber. Mirrors the existing fiber_ivar_persists_across_yield test
# but exercises the storage path instead of ivars.
f = Fiber.new do
  Fiber[:n] = 1
  Fiber.yield
  # After resume, the previous storage write is still visible.
  Fiber[:n] = Fiber[:n] + 1
  Fiber.yield
  Fiber[:n] = Fiber[:n] + 1
  puts Fiber[:n]
end

f.resume   # sets :n = 1
f.resume   # bumps to 2, yields
f.resume   # bumps to 3, prints 3
