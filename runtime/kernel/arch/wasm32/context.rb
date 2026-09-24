# A task's machine state on wasm32, which has none to save: a module
# runs on the one stack the engine keeps, and no call can switch it.
# A fiber never gets this far, since no stack is mapped for one.
CONTEXT_BYTES = 8

sig [Ptr, Word, Word] => Void
machine def zr_arch_context_start(ctx, entry, top)
end

sig [Ptr, Ptr] => Void
machine def zr_switch(from, to)
  zr_bug(Machine.bytes("a wasm32 module has one machine stack, and cannot switch it\n"), 60)
end
