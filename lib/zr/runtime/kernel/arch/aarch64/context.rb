# A task's saved machine state on aarch64. The zr_switch stub
# (`Backend::Aarch64::Stub`) saves the callee-saved registers, the frame
# and link registers, and the stack pointer into a context. Then it loads
# the registers from a different context.
Machine.raw "zr_switch"

CONTEXT_BYTES = 176

# Makes a context that starts at `entry` on the stack whose top is `top`
# when zr_switch loads it the first time. It sets the slots of the link
# register and the stack pointer.
sig [Ptr, Word, Word] => Void
machine def zr_arch_context_start(ctx, entry, top)
  Machine.store64(ctx, 88, entry)
  Machine.store64(ctx, 96, top)
end
