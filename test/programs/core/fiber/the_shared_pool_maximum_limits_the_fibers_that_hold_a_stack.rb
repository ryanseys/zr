# RUBY_SHARED_FIBER_POOL_MAXIMUM_COUNT limits the fibers that hold a
# stack. A fiber takes a stack when it first runs, and gives it back when
# it ends or when the GC frees it. At the limit, ruby runs a GC first,
# and raises FiberError when no stack becomes free.
GC.disable
held = Array.new(3) { Fiber.new { Fiber.yield; :done }.tap(&:resume) }

made = Fiber.new { :made }
p made.alive?
count = GC.count
error = (made.resume rescue $!)
p error.class, error.message
p GC.count > count

# The fiber that got no stack stays marked as resumed.
p made.alive?
p((made.resume rescue $!.message))

# A fiber that ends gives its stack back.
p held.shift.resume
p Fiber.new { :next }.resume

# So does a fiber that ends with an error.
failing = Fiber.new { raise "boom" }
p((failing.resume rescue $!.message))
p Fiber.new { :after_error }.resume

# A transfer to a new fiber takes a stack too. A transfer that gets none
# leaves no mark, so the same fiber runs when a stack is free.
held << Fiber.new { Fiber.yield; :done }.tap(&:resume)
moved = Fiber.new { :transferred }
p((moved.transfer rescue $!.class))
p held.pop.resume
p moved.transfer

# A fiber that never ran holds no stack.
idle = Array.new(10) { Fiber.new { :idle } }
p idle.size
p held.map(&:resume)
p idle.first(3).map(&:resume)

# Fibers that nothing reaches are freed by the GC that the limit runs,
# also while GC is disabled.
count = GC.count
40.times { Fiber.new { Fiber.yield }.resume }
p GC.count > count
