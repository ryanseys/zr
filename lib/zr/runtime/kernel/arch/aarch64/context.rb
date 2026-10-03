module Zr::Kern
  # A task's saved machine state on aarch64. The zr_switch stub
  # (`Backend::Aarch64::Stub`) saves the callee-saved registers, the frame
  # and link registers, and the stack pointer into a context. Then it loads
  # the registers from a different context.
  #: (ptr, ptr) -> void
  def zr_switch(from, to) = Machine.raw

  CONTEXT_BYTES = 176

  # Makes a context that starts at `entry` on the stack whose top is `top`
  # when zr_switch loads it the first time. It sets the slots of the link
  # register and the stack pointer.
  #: (ptr, word, word) -> void
  def zr_arch_context_start(ctx, entry, top)
    Machine.store64(ctx, 88, entry)
    Machine.store64(ctx, 96, top)
  end

  # The stack pointer that zr_switch saved in a context.
  #: (ptr) -> word
  def zr_arch_context_sp(ctx)
    Machine.load64(ctx, 96)
  end
end
