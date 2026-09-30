# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# class-method &blk used as a value (assigned to a local, then called): the
# call site must still pass the block proc
module V
  def self.take(&blk)
    p = blk
    p.call(9)
  end
end
V.take { |i| puts "val #{i}" }         # val 9

