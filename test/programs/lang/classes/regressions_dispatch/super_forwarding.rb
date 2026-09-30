# Bare `super` (no args, no parens) inside a constructor parses as
# `ForwardingSuperNode`, not `SuperNode`. It calls the parent's
# `initialize` with the same arguments, so the parent sets its ivars.

class T_super_forwarding_Base
  def initialize(x)
    @x = x
    @y = x * 10
  end
end

class T_super_forwarding_Child < T_super_forwarding_Base
  attr_reader :x, :y, :z
  def initialize(x)
    super              # bare — forwards x to T_super_forwarding_Base#initialize
    @z = x + 1
  end
end

c = T_super_forwarding_Child.new(3)
puts c.x   # 3
puts c.y   # 30
puts c.z   # 4
