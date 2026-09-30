# A method's &block parameter is reachable from a Thread.new / Fiber.new block
# in that method's body. The block runs as an independent closure on its own
# fiber stack, so the method must keep its &blk as a real Proc, and the call
# site must pass the block. This holds for a class or module method too.

# a positional parameter ahead of &blk, forwarded into the thread
module N
  def self.g(prefix, &blk)
    t = Thread.new { blk.call(prefix) }
    t.join
  end
end
N.g("x") { |s| puts "pre #{s}" }       # pre x

