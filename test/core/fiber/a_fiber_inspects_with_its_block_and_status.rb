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

__END__
#<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (created)>
#<Fiber:X (suspended by resuming)>
#<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (suspended by resuming)>
#<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:9 (suspended)>
#<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (terminated)>
true
#<Fiber:X(&:itself) (created)>
false
true
