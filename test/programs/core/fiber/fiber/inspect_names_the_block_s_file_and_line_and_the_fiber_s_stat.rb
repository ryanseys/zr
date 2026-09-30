# Fiber#inspect names the block's file and line and the fiber's status,
# as fiber_to_s writes it. A fiber that resumed another is suspended by
# resuming it; a thread's own fiber has no block.

def shown(fiber) = fiber.inspect.sub(/0x\h+/, "X")

root = Fiber.current
outer = Fiber.new do
  inner = Fiber.new do
    puts shown(root), shown(outer)
    Fiber.yield
  end
  inner.resume
  puts shown(inner)
end
puts shown(outer)
outer.resume
puts shown(outer), outer.to_s == outer.inspect
puts shown(Fiber.new(&:itself))
p Fiber.singleton_methods.include?(:new), Fiber.public_instance_methods(false).include?(:inspect)

