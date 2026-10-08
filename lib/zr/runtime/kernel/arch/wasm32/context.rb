module Zr::Kern
  # A task's machine state on wasm32. There is no state to save: a module
  # runs on the single stack of the engine, and no call can switch it.
  # A fiber never comes here, because no stack is mapped for it.
  CONTEXT_BYTES = 8

  #: (ptr, word, word) -> void
  def zr_arch_context_start(ctx, entry, top)
  end

  # A context saves no stack pointer here.
  #: (ptr) -> word
  def zr_arch_context_sp(ctx)
    0
  end

  #: (ptr, ptr) -> void
  def zr_switch(from, to)
    zr_bug(Machine.bytes("a wasm32 module has one machine stack, and cannot switch it\n"), 60)
  end

  # A wasm32 module calls no native C.
  #: (ptr, ptr, ptr, word) -> word
  def zr_cframe_call(record, fn, argv, argc)
    zr_bug(Machine.bytes("a wasm32 module cannot call native C\n"), 37)
    0
  end

  #: (ptr) -> void
  def zr_cframe_leap(record)
    zr_bug(Machine.bytes("a wasm32 module cannot call native C\n"), 37)
  end

  #: (ptr, ptr, ptr) -> word
  def zr_gc_call(fn, a, b)
    zr_bug(Machine.bytes("a wasm32 module cannot call native C\n"), 37)
    0
  end
end
