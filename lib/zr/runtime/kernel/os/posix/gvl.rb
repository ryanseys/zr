module Zr::Kern
  # Native threads with a GVL, on the OSes that have POSIX threads. Each
  # Ruby thread but the main one runs on an OS thread of its own, and
  # only the thread that holds the GVL runs Ruby. The scheduler in
  # core/thread.rb chooses which thread runs next, as it does for green
  # threads; its switch hands the GVL to that thread's OS thread, which
  # wakes in the fiber where it stopped, and the giver waits for its own
  # next turn.
  #
  # A handoff is a fiber switch split in two. The giver saves the words
  # that each thread keeps for itself (the lock plan's `:thread` rows: the
  # running fiber, its task and its kernel root frames) into its fiber;
  # the thread that wakes loads its own back, and its gate register. The
  # kernel's other state is the GVL holder's, as it is the running green
  # thread's, and a handoff comes only where a green switch would.
  #
  # Only the GVL holder takes asynchronous signals. A thread masks them
  # before it gives the GVL away and unmasks them when it wakes, so a
  # signal interrupts the blocking call of the thread that runs, as it
  # does on one OS thread.
  #
  # ZR_THREADS=native turns this on; by default threads stay green.

  # One thread's OS thread and its turn. The root fiber of each Ruby
  # thread has one (RFiber#native) from its first handoff.
  class ThreadState < Layout
    attr_accessor :mutex #: ptr
    attr_accessor :cond #: ptr
    # 1 from the handoff that gives this thread the GVL until it wakes.
    attr_accessor :turn #: word
    # The OS thread, or 0 until its first turn starts it.
    attr_accessor :pthread #: word
    # The thread's root fiber, whose stack the OS thread runs on.
    attr_accessor :fiber #: word
    # The context of the OS thread's own stack. A thread that ends
    # switches back to it, and gives the GVL to `next` from there.
    attr_accessor :entry #: ptr
    attr_accessor :next #: ptr
  end

  THREADS_GREEN = 1
  THREADS_NATIVE = 2

  # Whether threads are native: ZR_THREADS=native, read once.
  #: () -> bool
  def zr_threads_native
    mode = Machine.static(:threads_mode, 8)
    if Machine.load64(mode, 0) == 0
      v = Libc.getenv(Machine.bytes("ZR_THREADS\0"))
      native = v != 0 && zr_bytes_eq(v, zr_cstr_len(v), Machine.bytes("native"), 6)
      Machine.store64(mode, 0, native ? THREADS_NATIVE : THREADS_GREEN)
    end
    Machine.load64(mode, 0) == THREADS_NATIVE
  end

  #: () -> value
  def zr_threads_native_m
    zr_bool(zr_threads_native())
  end

  # The state of the thread whose root fiber is `root`. The first one of
  # the running thread names this OS thread; any other starts unstarted.
  #: (value, bool) -> ptr
  def zr_thread_state(root, running)
    ts = RFiber[root].native
    if ts != 0
      return ts
    end
    ts = zr_xmalloc(ThreadState.size)
    ThreadState[ts].mutex = zr_xmalloc(PTHREAD_OBJECT_BYTES)
    ThreadState[ts].cond = zr_xmalloc(PTHREAD_OBJECT_BYTES)
    Libc.pthread_mutex_init(ThreadState[ts].mutex, Machine.ptr(0))
    Libc.pthread_cond_init(ThreadState[ts].cond, Machine.ptr(0))
    ThreadState[ts].turn = 0
    ThreadState[ts].pthread = running ? Machine.word(Libc.pthread_self()) : 0
    ThreadState[ts].fiber = Machine.word(root)
    ThreadState[ts].entry = zr_xmalloc(CONTEXT_BYTES)
    ThreadState[ts].next = Machine.ptr(0)
    RFiber[root].native = ts
    ts
  end

  # Frees a root fiber's thread state with the fiber. Its OS thread has
  # ended or never started.
  #: (ptr) -> void
  def zr_thread_state_free(ts)
    Libc.pthread_mutex_destroy(ThreadState[ts].mutex)
    Libc.pthread_cond_destroy(ThreadState[ts].cond)
    zr_xfree(ThreadState[ts].mutex)
    zr_xfree(ThreadState[ts].cond)
    zr_xfree(ThreadState[ts].entry)
    zr_xfree(ts)
  end

  # The scheduler's switch to `to`, the fiber where another thread
  # stopped, with native threads: gives that thread the GVL and waits for
  # this one's next turn. A thread that has ended (`exiting`) waits for
  # none: its OS thread leaves the fiber's stack, gives the GVL away and
  # ends. Returns false with green threads, which switch fibers.
  #: (value, value, bool) -> bool
  def zr_native_switch(cur, to, exiting)
    if !zr_threads_native()
      return false
    end
    me = zr_thread_state(RFiber[cur].home, true)
    them = zr_thread_state(RFiber[to].home, false)
    RFiber[cur].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    zr_signals_mask(true)
    if exiting
      ThreadState[me].next = them
      zr_switch(RFiber[cur].ctx, ThreadState[me].entry)
    end
    zr_gvl_give(them)
    zr_gvl_wait(me)
    zr_gvl_enter(Machine.word(cur))
    zr_gates_reload()
    true
  end

  # Hands the GVL to `ts`, and starts its OS thread at its first turn.
  # The giver touches only `ts` from here, since the thread that wakes
  # owns the kernel's state.
  any_thread :zr_gvl_give

  #: (ptr) -> void
  def zr_gvl_give(ts)
    started = ThreadState[ts].pthread != 0
    Libc.pthread_mutex_lock(ThreadState[ts].mutex)
    ThreadState[ts].turn = 1
    Libc.pthread_cond_broadcast(ThreadState[ts].cond)
    Libc.pthread_mutex_unlock(ThreadState[ts].mutex)
    if !started
      tid = Machine.slot(8)
      if Libc.pthread_create(tid, Machine.ptr(0), Machine.addr(:zr_thread_entry), ts) != Machine.i32(0)
        zr_bug(Machine.bytes("can't create a native thread\n"), 29)
      end
      ThreadState[ts].pthread = Machine.load64(tid, 0)
      Libc.pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
    end
  end

  # Waits until a handoff gives this thread the GVL.
  any_thread :zr_gvl_wait

  #: (ptr) -> void
  def zr_gvl_wait(ts)
    Libc.pthread_mutex_lock(ThreadState[ts].mutex)
    while ThreadState[ts].turn == 0
      Libc.pthread_cond_wait(ThreadState[ts].cond, ThreadState[ts].mutex)
    end
    ThreadState[ts].turn = 0
    Libc.pthread_mutex_unlock(ThreadState[ts].mutex)
  end

  # The thread holds the GVL again, in fiber `f`: the per-thread words are
  # its own, and it takes signals. Its caller reloads the gate register
  # (zr_gates_reload).
  any_thread :zr_gvl_enter

  #: (word) -> void
  def zr_gvl_enter(f)
    Machine.store64(Machine.static(:current_fiber, 8), 0, f)
    Machine.store64(zr_current_task_slot(), 0, Machine.word(RFiber[Machine.value(f)].task))
    Machine.store64(zr_kroots(), 0, Machine.word(RFiber[Machine.value(f)].kroots))
    zr_signals_mask(false)
  end

  # The start of a thread's OS thread, at its first turn: it runs the
  # thread's root fiber on that fiber's stack. When the thread ends, the
  # fiber switches back here, and this OS thread gives the GVL to the
  # thread that runs next and ends. It reads nothing of `ts` after that
  # handoff, since the fiber and its state may be freed from then on.
  any_thread :zr_thread_entry

  #: (ptr) -> ptr
  def zr_thread_entry(ts)
    Machine.gates_enter
    altstack = zr_crash_thread_init()
    zr_gvl_wait(ts)
    zr_gvl_enter(ThreadState[ts].fiber)
    zr_gates_reload()
    zr_switch(ThreadState[ts].entry, RFiber[Machine.value(ThreadState[ts].fiber)].ctx)
    zr_gvl_give(ThreadState[ts].next)
    zr_crash_thread_end(altstack)
    Machine.ptr(0)
  end

  # Loads the gate register from the gate word, which other threads set
  # while this one waited. Not with Machine.gates_enter: a def that enters
  # from foreign code gives its caller back the register it had.
  #: () -> void
  def zr_gates_reload
    Machine.gates_set(Machine.load64(Machine.static(:gates, 8), 0))
  end

  # The OS thread of a native thread takes a fatal signal on an
  # alternate stack of its own, since each OS thread has one. Returns
  # the stack, or 0.
  any_thread :zr_crash_thread_init

  #: () -> ptr
  def zr_crash_thread_init
    stack = zr_os_stack_map(CRASH_STACK_BYTES)
    if stack != 0
      zr_os_altstack(stack, CRASH_STACK_BYTES)
    end
    stack
  end

  # The OS thread ends: its alternate stack goes.
  any_thread :zr_crash_thread_end

  #: (ptr) -> void
  def zr_crash_thread_end(stack)
    if stack != 0
      zr_os_altstack_off()
      Libc.munmap(stack, CRASH_STACK_BYTES)
    end
  end

  # Masks the asynchronous signals of this OS thread, or unmasks them all.
  # The synchronous ones (SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS and
  # SIGSEGV, which a fault raises in the thread that faults) are never
  # masked. Each OS's sigset_t is a little-endian bit set from signal 1,
  # in at most 128 bytes.
  any_thread :zr_signals_mask

  #: (bool) -> void
  def zr_signals_mask(masked)
    set = Machine.slot(128)
    Libc.memset(set, Machine.i32(masked ? 255 : 0), 128)
    if masked
      zr_sigset_clear(set, SIGNAL_ILL)
      zr_sigset_clear(set, 5)
      zr_sigset_clear(set, SIGNAL_ABRT)
      zr_sigset_clear(set, 8)
      zr_sigset_clear(set, SIGNAL_BUS)
      zr_sigset_clear(set, SIGNAL_SEGV)
    end
    Libc.pthread_sigmask(Machine.i32(SIG_SETMASK), set, Machine.ptr(0))
  end

  any_thread :zr_sigset_clear

  #: (ptr, word) -> void
  def zr_sigset_clear(set, signo)
    at = set + ((signo - 1) >> 3)
    Machine.store8(at, 0, Machine.i8(Machine.u8(Machine.load8(at, 0)) & (255 - (1 << ((signo - 1) & 7)))))
  end
end
