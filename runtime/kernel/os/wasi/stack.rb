# WASI machine stacks. A module has one stack. The engine sets its limit
# and does not tell the module that limit. A module cannot map memory for
# a second stack.

sig [I32, Ptr] => I32
machine def zr_os_main(argc, argv)
  zr_main(argc, argv)
end

# 0: the stack check never fails. The engine's own limit stops a
# recursion that is too deep.
sig [] => Word
machine def zr_os_stack_low
  0
end

# 0: the module cannot get access to the engine's stack.
sig [] => Word
machine def zr_os_stack_high
  0
end

sig [Word] => Ptr
machine def zr_os_stack_map(bytes)
  zr_os_set_errno(WASI_ENOSYS)
  Machine.ptr(0)
end

# There is no timer thread. The preemption count is the clock (send.rb).
sig [] => Void
machine def zr_os_poll_start
end
