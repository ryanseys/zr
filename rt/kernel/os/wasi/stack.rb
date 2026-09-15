# WASI's machine stacks: a module has one, which the engine bounds and
# does not describe, and it maps no memory for another.

# 0: the stack check never trips, and the engine's own bound stops a
# recursion that runs too deep.
sig [] => Word
machine def zr_os_stack_low
  0
end

sig [Word] => Ptr
machine def zr_os_stack_map(bytes)
  zr_os_set_errno(WASI_ENOSYS)
  Machine.ptr(0)
end
