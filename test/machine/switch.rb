# Two stacks, one million switches between them: the context-switch stub
# is a raw function this unit carries, on either road.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :mmap, [Ptr, Word, I32, I32, I32, Word] => Ptr
  Libc.import :exit, [I32] => Void
  raw :zr_switch, [Ptr, Ptr] => Void

  # The other stack's body: bounce back forever.
  sig [] => Void
  def other
    ctx = Machine.static(:ctx, 512)
    while true
      zr_switch(ctx + 256, ctx)
    end
  end

  sig [I32, Ptr] => I32
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
