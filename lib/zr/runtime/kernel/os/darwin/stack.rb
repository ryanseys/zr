module Zr::Kern
  # darwin machine stacks: the stack of the main thread, and how zr maps
  # a fiber stack.

  # The program runs on the stack of the main thread. The linker sets its
  # size to `Native::Link::STACK` bytes.
  #: (i32, ptr) -> i32
  def zr_os_main(argc, argv)
    zr_main(argc, argv)
  end

  # The lowest address of this thread's stack, or 0 if the host does not
  # give it.
  #: () -> word
  def zr_os_stack_low
    me = Libc.pthread_self()
    size = Libc.pthread_get_stacksize_np(me)
    top = Libc.pthread_get_stackaddr_np(me)
    if top == 0
      return 0
    end
    Machine.word(top) - size
  end

  # The address immediately after the top of this thread's stack, or 0 if
  # the host does not give it.
  #: () -> word
  def zr_os_stack_high
    Machine.word(Libc.pthread_get_stackaddr_np(Libc.pthread_self()))
  end

  # PROT_READ | PROT_WRITE, and MAP_PRIVATE | MAP_ANON.
  STACK_PROT = 3
  STACK_MAP_FLAGS = 4098
  # The guard at the bottom of each fiber stack, which faults on access:
  # one page on arm64 macOS.
  STACK_GUARD_BYTES = 16384

  # Maps a stack of `bytes` with a guard as its lowest page. Returns 0 and
  # sets errno on failure. The system supplies the pages only when the
  # stack grows into them.
  #: (word) -> ptr
  def zr_os_stack_map(bytes)
    stack = Libc.mmap(0, bytes, Machine.i32(STACK_PROT), Machine.i32(STACK_MAP_FLAGS), -1, 0)
    # MAP_FAILED, or no stack because the host has no mmap.
    if Machine.word(stack) == 0 - 1 || Machine.word(stack) == 0
      return Machine.ptr(0)
    end
    # The lowest page faults on access. Thus a kernel routine that goes
    # past the margin below the stack check stops there. It does not write
    # into the memory below the stack.
    Libc.mprotect(stack, STACK_GUARD_BYTES, Machine.i32(0))
    stack
  end

  # The timer thread for preemption (send.rb). After a second Ruby thread
  # starts, it sets the poll word every 100 ms. Thus a thread that
  # computes with no call into the kernel yields to the scheduler at its
  # next back edge or method entry, as with CRuby's timer thread.
  #: (ptr) -> ptr
  def zr_poll_timer(arg)
    Machine.gates_enter
    ts = Machine.slot(16)
    Machine.store64(ts, 0, 0)
    Machine.store64(ts, 8, 100000000)
    while true
      Libc.nanosleep(ts, 0)
      zr_poll_set()
    end
    arg
  end

  #: () -> void
  def zr_os_poll_start
    started = Machine.static(:poll_started, 8)
    if Machine.load64(started, 0) != 0
      return
    end
    Machine.store64(started, 0, 1)
    tid = Machine.slot(8)
    if Libc.pthread_create(tid, 0, Machine.addr(:zr_poll_timer), 0) == Machine.i32(0)
      Libc.pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
    end
  end
end
