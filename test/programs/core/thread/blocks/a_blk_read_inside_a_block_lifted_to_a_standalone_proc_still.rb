# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# &blk read inside a block that is *lifted* to a standalone proc (passed to a
# method that keeps a real &block param): the same capture-escape as the
# Thread case, so the method must keep a heap &blk too
def taker(&t)
  t
end

def outer(&blk)
  pr = taker { blk.call(4) }
  pr.call
end
outer { |i| puts "lift #{i}" }         # lift 4

