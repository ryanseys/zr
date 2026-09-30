# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# module (class-)method: &blk captured by a Thread.new block
module M
  def self.f(&blk)
    t = Thread.new { blk.call(0) }
    t.join
  end
end
M.f { |i| puts "got #{i}" }            # got 0

