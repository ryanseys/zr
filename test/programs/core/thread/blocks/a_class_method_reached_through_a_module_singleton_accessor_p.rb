# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# a class method reached through a module singleton accessor must also pass
# the block proc -- Stage-1: the accessor is bound to exactly one constant
module Reg1
  class << self
    attr_accessor :handler
  end
end

class H1
  def self.run(x, &blk)
    t = Thread.new { blk.call(x) }
    t.join
  end
end

Reg1.handler = H1
Reg1.handler.run(5) { |v| puts "reg1 #{v}" }   # reg1 5

