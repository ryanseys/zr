module Zr::Kern
  # A task's saved machine state on x86_64. The zr_switch stub
  # (`Backend::X86_64::Stub`) saves rbx, rbp, r12..r15, rsp, the address
  # to resume at, and the SSE and x87 control words into a context. Then
  # it loads the registers from a different context.
  #: (ptr, ptr) -> void
  def zr_switch(from, to) = Machine.raw

  CONTEXT_BYTES = 72

  # Makes a context that starts at `entry` on the stack whose top is `top`
  # when zr_switch loads it the first time: a jump to `entry` with rsp
  # where a call would leave it (a zero return address below the 16-byte
  # aligned top), and the default control words.
  #: (ptr, word, word) -> void
  def zr_arch_context_start(ctx, entry, top)
    Machine.store64(Machine.ptr(top - 8), 0, 0)
    Machine.store64(ctx, 48, top - 8)
    Machine.store64(ctx, 56, entry)
    # mxcsr 0x1F80 at 64, the x87 control word 0x037F at 68.
    Machine.store64(ctx, 64, 0x037F_0000_1F80)
  end

  # The stack pointer that zr_switch saved in a context.
  #: (ptr) -> word
  def zr_arch_context_sp(ctx)
    Machine.load64(ctx, 48)
  end

  # Calls the C function `fn` with the `argc` words at `argv` (at least
  # eight words), after it saves a context in the C frame record `record`
  # (`CFrame`). It returns C's result, or undef when a C-API function
  # leaps back with zr_cframe_leap.
  #: (ptr, ptr, ptr, word) -> word
  def zr_cframe_call(record, fn, argv, argc) = Machine.raw

  # Resumes the context in `record`: its zr_cframe_call returns undef.
  #: (ptr) -> void
  def zr_cframe_leap(record) = Machine.raw

  # Calls the C function `fn(a, b)`, for the collector.
  #: (ptr, ptr, ptr) -> word
  def zr_gc_call(fn, a, b) = Machine.raw
end
