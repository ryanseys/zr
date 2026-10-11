# A Fiber whose block is a Method object runs that method, with no frame
# of the program under it (test_fiber.rb's test_no_valid_cfp).
p Fiber.new(&Module.method(:nesting)).resume
k = Class.new { def to_s = "k" }
p Fiber.new(&k.method(:undef_method)).resume(:to_s).equal?(k)
p k.method_defined?(:to_s)
p Fiber.new(&method(:Integer)).resume("42")
p Fiber.new(&[1, 2, 3].method(:sum)).resume
p Fiber.new(&:upcase.to_proc).resume("abc")
def gen = Fiber.yield(:first) + 1
f = Fiber.new(&method(:gen))
p f.resume, f.resume(41)
p Thread.new(&Module.method(:nesting)).value
