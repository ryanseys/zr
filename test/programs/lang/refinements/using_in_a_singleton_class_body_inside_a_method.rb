# `using` is permitted in a `class << self` body, also when a method holds
# the body. A refinement made later for a frozen class still applies.
def activate
  class << self
    c = Class.new { def foo = :cfoo }
    m = Module.new { refine(c) { def foo = :rfoo } }
    using m
    p c.new.foo
    c.freeze
    m.module_eval { refine(c) { def bar = :rbar } }
    p c.new.bar
  end
end
activate
p((Module.new { def self.go = using(Module.new) }.go rescue $!.message))
