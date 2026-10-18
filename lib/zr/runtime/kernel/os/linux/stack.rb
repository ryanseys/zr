module Zr::Kern
  # Linux machine stacks. The main thread's stack grows only to the
  # RLIMIT_STACK limit (8 MiB unless the shell sets a different value), and
  # a binary cannot request more. So the program runs on its own stack,
  # which zr maps as it maps a fiber stack.

  # The program runs on its own stack (zr_main_on_own_stack).
  #: (i32, ptr) -> i32
  def zr_os_main(argc, argv)
    zr_main_on_own_stack(argc, argv)
  end

  # The lowest address of the program's stack, or 0 if it runs on the
  # process's own stack.
  #: () -> word
  def zr_os_stack_low
    zr_program_stack_low()
  end

  # The address immediately after the top of the program's stack, or 0 if
  # it runs on the process's own stack.
  #: () -> word
  def zr_os_stack_high
    zr_program_stack_high()
  end

  # This OS thread's id, as gettid gives it.
  any_thread :zr_os_thread_id

  #: () -> word
  def zr_os_thread_id
    Machine.u32(Libc.gettid())
  end

  # PROT_READ | PROT_WRITE, and MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK.
  STACK_PROT = 3
  STACK_MAP_FLAGS = 131106
  # The guard page at the bottom of each stack, which faults on access.
  STACK_GUARD_BYTES = 4096

  # Maps a stack of `bytes` with a guard as its lowest page. Returns 0 and
  # sets errno on failure. The system supplies the pages only when the
  # stack grows into them.
  #: (word) -> ptr
  def zr_os_stack_map(bytes)
    stack = Libc.mmap(0, bytes, Machine.i32(STACK_PROT), Machine.i32(STACK_MAP_FLAGS), -1, 0)
    if Machine.word(stack) == 0 - 1
      return Machine.ptr(0)
    end
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
    # The thread that runs Ruby takes the signals, not the timer.
    zr_signals_mask(true)
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
