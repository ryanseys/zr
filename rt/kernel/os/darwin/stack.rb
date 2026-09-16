# darwin's machine stacks: the main thread's, and how a fiber's is
# mapped.
Machine.import "pthread_self", [] => Ptr
Machine.import "pthread_get_stackaddr_np", [Ptr] => Ptr
Machine.import "pthread_get_stacksize_np", [Ptr] => Word
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "mprotect", [Ptr, Word, I32] => I32

# The program runs on the main thread's own stack, which the link asks
# to be `Native::Link::STACK` bytes.
sig [I32, Ptr] => I32
machine def zr_os_main(argc, argv)
  zr_main(argc, argv)
end

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

# The address just past the top of this thread's stack, or 0 where the
# host does not say.
sig [] => Word
machine def zr_os_stack_high
  Machine.word(pthread_get_stackaddr_np(pthread_self()))
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

# The timer thread of the preemption (send.rb): once a second Ruby
# thread started, it sets the poll word every 100 ms, so that a thread
# computing with no call into the kernel hands the turn on at its next
# back edge or method entry, as CRuby's timer thread has it do.
Machine.import "pthread_create", [Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "pthread_detach", [Ptr] => I32

sig [Ptr] => Ptr
machine def zr_os_poll_timer(arg)
  ts = Machine.slot(16)
  Machine.store64(ts, 0, 0)
  Machine.store64(ts, 8, 100000000)
  while true
    nanosleep(ts, 0)
    zr_poll_set()
  end
  arg
end

sig [] => Void
machine def zr_os_poll_start
  started = Machine.static(:poll_started, 8)
  if Machine.load64(started, 0) != 0
    return
  end
  Machine.store64(started, 0, 1)
  tid = Machine.slot(8)
  if pthread_create(tid, 0, Machine.addr(:zr_os_poll_timer), 0) == Machine.i32(0)
    pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
  end
end
