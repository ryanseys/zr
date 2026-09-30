# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# class-method &blk with a value-returning call, summed across two invocations
module S
  def self.calc(&blk)
    blk.call(1) + blk.call(2)
  end
end
puts S.calc { |i| i * 10 }             # 30

