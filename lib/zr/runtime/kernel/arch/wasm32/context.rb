# A task's machine state on wasm32. There is no state to save: a module
# runs on the single stack of the engine, and no call can switch it.
# A fiber never comes here, because no stack is mapped for it.
CONTEXT_BYTES = 8

sig [Ptr, Word, Word] => Void
machine def zr_arch_context_start(ctx, entry, top)
end

# A context saves no stack pointer here.
sig [Ptr] => Word
machine def zr_arch_context_sp(ctx)
  0
end

sig [Ptr, Ptr] => Void
machine def zr_switch(from, to)
  zr_bug(Machine.bytes("a wasm32 module has one machine stack, and cannot switch it\n"), 60)
end
