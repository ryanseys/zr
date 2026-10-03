# Two stacks, one million switches between them: the context-switch stub
# is a raw function this unit carries, on either road.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (ptr, word, i32, i32, i32, word) -> ptr
    def self.mmap(p, n1, i1, i2, i3, n2) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
  end

  #: (ptr, ptr) -> void
  def zr_switch(p1, p2) = Machine.raw

  # The other stack's body: bounce back forever.
  #: () -> void
  def other
    ctx = Machine.static(:ctx, 512)
    while true
      zr_switch(ctx + 256, ctx)
    end
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    ctx = Machine.static(:ctx, 512)
    other_ctx = ctx + 256
    stack = Libc.mmap(0, 65536, 3, 4098, -1, 0)
    Machine.store64(other_ctx, 88, Machine.addr(:other))
    Machine.store64(other_ctx, 96, stack + 65536)
    n = 0
    while n < 1000000
      zr_switch(ctx, other_ctx)
      n += 1
    end
    Libc.write(1, Machine.bytes("done\n"), 5)
    Libc.exit(0)
    0
  end
end
