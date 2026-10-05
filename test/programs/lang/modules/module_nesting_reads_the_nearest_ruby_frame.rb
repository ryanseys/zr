# Module.nesting reads the nearest frame of Ruby code, as rb_vm_cref does,
# so a call that the core makes in a fresh Fiber gives no nesting
# (test_fiber.rb's test_no_valid_cfp).
module A
  class B
    p Module.nesting, Module.method(:nesting).call, [1].map { Module.nesting }.first
    def self.m = Module.nesting
    p Fiber.new(&Module.method(:nesting)).resume
    p Fiber.new { Module.nesting }.resume
    p eval("Module.nesting")
  end
end
p A::B.m, Module.nesting
p Fiber.new(&Class.new.method(:undef_method)).resume(:to_s).class
