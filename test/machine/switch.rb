# Two stacks, one million switches between them: the context-switch stub
# is a raw function this unit carries, on either road.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "exit", [I32] => Void
Machine.raw "zr_switch"

# The other stack's body: bounce back forever.
sig [] => Void
machine def other
  ctx = Machine.static(:ctx, 512)
  while true
    zr_switch(ctx + 256, ctx)
  end
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  ctx = Machine.static(:ctx, 512)
  other_ctx = ctx + 256
  stack = mmap(0, 65536, 3, 4098, -1, 0)
  Machine.store64(other_ctx, 88, Machine.addr(:other))
  Machine.store64(other_ctx, 96, stack + 65536)
  n = 0
  while n < 1000000
    zr_switch(ctx, other_ctx)
    n += 1
  end
  write(1, Machine.bytes("done\n"), 5)
  exit(0)
  0
end
