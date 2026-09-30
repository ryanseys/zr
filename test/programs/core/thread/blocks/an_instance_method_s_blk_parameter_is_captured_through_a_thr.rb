# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# instance method: same capture through a thread
class C
  def run(&blk)
    t = Thread.new { blk.call(7) }
    t.join
  end
end
C.new.run { |i| puts "run #{i}" }      # run 7

