# Cooperative fibers each hold their own GC roots. A fiber switch
# via non-LIFO yields / Fiber.transfer must not let one fiber
# change the roots of another. Thus a GC pass from the second
# fiber keeps the live locals of the first fiber.

class Holder
  attr_reader :data
  def initialize(label)
    @data = "holder_" + label
  end
end

# Build a small amount of garbage on every iteration to coax the
# allocator into running a GC pass while fibers are suspended.
def churn(n)
  i = 0
  s = ""
  while i < n
    s = s + i.to_s + ","
    i += 1
  end
  s.length
end

results = []

f1 = Fiber.new do
  h1 = Holder.new("one")
  Fiber.yield
  # If h1 got collected during f2's churn, this read would
  # segfault or return garbage.
  results.push(h1.data)
end

f2 = Fiber.new do
  h2 = Holder.new("two")
  Fiber.yield
  results.push(h2.data)
end

f3 = Fiber.new do
  h3 = Holder.new("three")
  Fiber.yield
  results.push(h3.data)
end

# Resume each fiber once — they push their roots and yield.
f1.resume
f2.resume
f3.resume

# Now hammer the allocator. Any of the three fibers' h1/h2/h3
# locals that were clobbered will surface as stale memory.
n = 0
while n < 50
  churn(20)
  n += 1
end

# Resume each fiber — they read their saved local.
f3.resume
f1.resume
f2.resume

puts results.length
i = 0
while i < results.length
  puts results[i]
  i += 1
end
