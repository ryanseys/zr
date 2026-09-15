# A task's saved machine state on aarch64: the zr_switch stub
# (`Backend::Aarch64::Stub`) saves the callee-saved registers, the frame
# and link registers and the stack pointer into a context and loads
# another's.
Machine.raw "zr_switch"

CONTEXT_BYTES = 176

# A context that starts at `entry` on a stack whose top is `top`, the
# first time zr_switch loads it: the link register and the stack
# pointer's slots.
sig [Ptr, Word, Word] => Void
machine def zr_arch_context_start(ctx, entry, top)
  Machine.store64(ctx, 88, entry)
  Machine.store64(ctx, 96, top)
end
