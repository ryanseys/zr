# Fiber.new is Class#new: allocate makes a fiber that refuses to run, and
# initialize checks the storage, then the block, then whether the fiber
# was made already, as rb_fiber_initialize_kw does. A subclass makes its
# fiber through super.

class Doubler < Fiber
  def initialize(x)
    super() { Fiber.yield(x * 2); x * 3 }
  end
end
d = Doubler.new(4)
p d.resume, d.resume, d.class
f = Fiber.allocate
[-> { f.resume }, -> { f.alive? }, -> { Fiber.new }, -> { Fiber.new {}.send(:initialize) {} },
 -> { Fiber.new(storage: 1) {} }, -> { Fiber.new(storage: {"a" => 1}) {} }, -> { Fiber.new(storage: {}.freeze) {} },
 -> { Fiber.new(storage: false) {} }].each do |bad|
  bad.call
rescue => e
  p e
end
Fiber[:k] = 1
p Fiber.new { Fiber[:k] }.resume, Fiber.new(storage: nil) { Fiber[:k] }.resume, Fiber.new(storage: {k: 2}) { Fiber[:k] }.resume
p Fiber.new(blocking: true) { Fiber.current.blocking? }.resume, Fiber.new(pool: nil) { 1 }.resume
p Fiber.instance_method(:initialize).owner, Fiber.singleton_methods.include?(:new), Fiber.respond_to?(:new)
p Fiber.new { 1 }.dup.alive? rescue p $!

