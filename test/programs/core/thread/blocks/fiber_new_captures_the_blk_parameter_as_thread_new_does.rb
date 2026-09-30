# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# Fiber.new capture of the &blk param
module F
  def self.h(&blk)
    fib = Fiber.new { blk.call(3) }
    fib.resume
  end
end
F.h { |i| puts "fib #{i}" }            # fib 3

