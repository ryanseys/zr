# darwin's machine stacks: where the main thread's ends, and how a
# fiber's is mapped.
Machine.import "pthread_self", [] => Ptr
Machine.import "pthread_get_stackaddr_np", [Ptr] => Ptr
Machine.import "pthread_get_stacksize_np", [Ptr] => Word
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "mprotect", [Ptr, Word, I32] => I32

# The lowest address of this thread's stack, or 0 where the host does
# not say.
sig [] => Word
machine def zr_os_stack_low
  me = pthread_self()
  size = pthread_get_stacksize_np(me)
  top = pthread_get_stackaddr_np(me)
  if top == 0
    return 0
  end
  Machine.word(top) - size
end

# PROT_READ | PROT_WRITE, and MAP_PRIVATE | MAP_ANON.
STACK_PROT = 3
STACK_MAP_FLAGS = 4098
# The lowest page of each fiber stack, which faults on touch: one page
# on arm64 macOS.
STACK_GUARD_BYTES = 16384

# A stack of `bytes`, its lowest page a guard, or 0 with errno set. The
# pages arrive only as the stack grows into them.
sig [Word] => Ptr
machine def zr_os_stack_map(bytes)
  stack = mmap(0, bytes, Machine.i32(STACK_PROT), Machine.i32(STACK_MAP_FLAGS), -1, 0)
  # MAP_FAILED, or no stack at all where the host has no mmap.
  if Machine.word(stack) == 0 - 1 || Machine.word(stack) == 0
    return Machine.ptr(0)
  end
  # The lowest page faults on touch, so a kernel routine that runs past
  # the margin below the stack check stops there, rather than writing
  # into whatever is mapped below.
  mprotect(stack, STACK_GUARD_BYTES, Machine.i32(0))
  stack
end
