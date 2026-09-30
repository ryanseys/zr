# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# Stage-2: the accessor is written with two distinct constants, so the call
# dispatches over the stored class -- each branch passes the same block proc
module Reg2
  class << self
    attr_accessor :handler
  end
end

class H2a
  def self.run(x, &blk)
    t = Thread.new { blk.call(x + 1) }
    t.join
  end
end

class H2b
  def self.run(x, &blk)
    t = Thread.new { blk.call(x + 2) }
    t.join
  end
end

Reg2.handler = H2a
Reg2.handler.run(10) { |v| puts "reg2a #{v}" } # reg2a 11
Reg2.handler = H2b
Reg2.handler.run(10) { |v| puts "reg2b #{v}" } # reg2b 12
