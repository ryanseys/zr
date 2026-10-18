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
    # The OS thread (pthread_t), or 0 until Thread.new starts it, and its
    # id (Thread#native_thread_id), or 0 until it has run.
    attr_accessor :pthread #: word
    attr_accessor :tid #: word
    # The thread's root fiber, whose stack the OS thread runs on.
    attr_accessor :fiber #: word
    # The context of the OS thread's own stack. A thread that ends
    # switches back to it, and gives the GVL to `next` from there.
    attr_accessor :entry #: ptr
    attr_accessor :next #: ptr
    # 1 while the thread runs C without the GVL (a region), in fiber
    # `cur`; `ubf(ubf_data)` stops that C for an interrupt.
    attr_accessor :region #: word
    attr_accessor :cur #: word
    attr_accessor :ubf #: ptr
    attr_accessor :ubf_data #: ptr
    # The next thread in the GVL's list of threads back from a region.
    attr_accessor :back #: ptr
    # 1 when the thread ended before its first turn: its OS thread ends.
    attr_accessor :cancel #: word
  end

  # The GVL's state for the threads that run C without it. The GVL
  # holder hands the GVL on at a switch; a thread that comes back from a
  # region takes it while it is free, or joins `back` and waits for a
  # switch to it. It sets the poll word and writes to the pipe, so the
  # holder's next safe point or idle wait moves it to the run queue. The
  # mutex guards `free` and `back`.
  class Gvl < Layout
    attr_accessor :mutex #: ptr
    attr_accessor :free #: word
    attr_accessor :back #: ptr
    attr_accessor :wake_r #: word
    attr_accessor :wake_w #: word
    # The thread-local key of a thread's state while it runs a region.
    attr_accessor :key #: word
  end

  # rb_thread_call_without_gvl's RUBY_UBF_IO and RUBY_UBF_PROCESS: a
  # signal ends the C's system call (ubf_select).
  UBF_SIGNAL = 0 - 1
  # The signal that ends it: SIGVTALRM, as ruby's ubf uses, with a handler
  # that does nothing and restarts no call.
  SIGNAL_VTALRM = 26

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
  # the running thread names this OS thread; any other has no OS thread
  # until zr_thread_spawn or its first turn starts one.
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
    ThreadState[ts].tid = running ? zr_os_thread_id() : 0
    ThreadState[ts].fiber = Machine.word(root)
    ThreadState[ts].entry = zr_xmalloc(CONTEXT_BYTES)
    ThreadState[ts].next = Machine.ptr(0)
    ThreadState[ts].region = 0
    ThreadState[ts].back = Machine.ptr(0)
    ThreadState[ts].cancel = 0
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
    if !started && zr_thread_start(ts) != 0
      zr_bug(Machine.bytes("can't create a native thread\n"), 29)
    end
  end

  # Starts the OS thread of `ts`, which waits for its first turn. Returns
  # 0, or pthread_create's error.
  any_thread :zr_thread_start

  #: (ptr) -> word
  def zr_thread_start(ts)
    tid = Machine.slot(8)
    err = Machine.u32(Libc.pthread_create(tid, Machine.ptr(0), Machine.addr(:zr_thread_entry), ts))
    if err == 0
      ThreadState[ts].pthread = Machine.load64(tid, 0)
      Libc.pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
    end
    err
  end

  # Thread.new with native threads: the thread's OS thread starts now, as
  # in ruby, and waits for its first turn. Raises ThreadError as
  # thread_create_core does when the OS gives no thread.
  #: (value) -> value
  def zr_thread_spawn(root)
    if !zr_threads_native()
      return Machine.value(QNIL)
    end
    err = zr_thread_start(zr_thread_state(root, false))
    if err != 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't create Thread: "), 21)
      text = Libc.strerror(Machine.i32(err))
      zr_buf_push(b, text, zr_cstr_len(text))
      return zr_raise_buf(zr_core_class(Machine.id(:ThreadError)), b)
    end
    Machine.value(QNIL)
  end

  # Thread#native_thread_id with native threads: the OS's id of the
  # thread's OS thread, which a thread that has not run yet gives as soon
  # as its OS thread has started. Nil with green threads.
  #: (value) -> value
  def zr_thread_native_id(root)
    if !zr_threads_native()
      return Machine.value(QNIL)
    end
    running = root == RFiber[zr_fiber_current()].home
    ts = zr_thread_state(root, running)
    if ThreadState[ts].pthread == 0 && zr_thread_start(ts) != 0
      return Machine.value(QNIL)
    end
    Libc.pthread_mutex_lock(ThreadState[ts].mutex)
    while ThreadState[ts].tid == 0
      Libc.pthread_cond_wait(ThreadState[ts].cond, ThreadState[ts].mutex)
    end
    Libc.pthread_mutex_unlock(ThreadState[ts].mutex)
    zr_fix(ThreadState[ts].tid)
  end

  # A thread that ends before its first turn (Thread#kill of a new
  # thread): its OS thread, which waits for that turn, ends instead.
  #: (value) -> value
  def zr_thread_cancel(root)
    ts = RFiber[root].native
    if ts != 0 && ThreadState[ts].pthread != 0
      ThreadState[ts].cancel = 1
      zr_gvl_give(ts)
    end
    Machine.value(QNIL)
  end

  # The pthread_t of a thread's OS thread, as the deadlock report names it
  # (`native:`), or nil with green threads.
  #: (value) -> value
  def zr_thread_pthread(root)
    if !zr_threads_native() || RFiber[root].native == 0
      return Machine.value(QNIL)
    end
    zr_fix(ThreadState[RFiber[root].native].pthread)
  end

  # In a forked child only the thread that forked runs: its OS thread has a
  # new id, and the GVL's lock and pipe are the child's own.
  #: () -> value
  def zr_gvl_after_fork
    if !zr_threads_native()
      return Machine.value(QNIL)
    end
    ts = zr_thread_state(RFiber[zr_fiber_current()].home, true)
    ThreadState[ts].pthread = Machine.word(Libc.pthread_self())
    ThreadState[ts].tid = zr_os_thread_id()
    g = Machine.static(:gvl, Gvl.size)
    if Gvl[g].mutex != 0
      Libc.close(Machine.i32(Gvl[g].wake_r))
      Libc.close(Machine.i32(Gvl[g].wake_w))
      zr_xfree(Gvl[g].mutex)
      Gvl[g].mutex = Machine.ptr(0)
      Gvl[g].free = 0
      Gvl[g].back = Machine.ptr(0)
      zr_gvl()
    end
    Machine.value(QNIL)
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
    # Its id, for Thread#native_thread_id, which may wait for it.
    Libc.pthread_mutex_lock(ThreadState[ts].mutex)
    ThreadState[ts].tid = zr_os_thread_id()
    Libc.pthread_cond_broadcast(ThreadState[ts].cond)
    Libc.pthread_mutex_unlock(ThreadState[ts].mutex)
    zr_gvl_wait(ts)
    if ThreadState[ts].cancel != 0
      zr_crash_thread_end(altstack)
      return Machine.ptr(0)
    end
    zr_gvl_enter(ThreadState[ts].fiber)
    zr_gates_reload()
    zr_switch(ThreadState[ts].entry, RFiber[Machine.value(ThreadState[ts].fiber)].ctx)
    # A thread that ended with the GVL free gives it to nobody.
    if ThreadState[ts].next != 0
      zr_gvl_give(ThreadState[ts].next)
    end
    zr_crash_thread_end(altstack)
    Machine.ptr(0)
  end

  # The GVL's region state, made at the first region.
  #: () -> ptr
  def zr_gvl
    g = Machine.static(:gvl, Gvl.size)
    if Gvl[g].mutex != 0
      return g
    end
    Gvl[g].mutex = zr_xmalloc(PTHREAD_OBJECT_BYTES)
    Libc.pthread_mutex_init(Gvl[g].mutex, Machine.ptr(0))
    key = Machine.slot(8)
    Machine.store64(key, 0, 0)
    Libc.pthread_key_create(key, Machine.ptr(0))
    Gvl[g].key = Machine.load64(key, 0)
    fds = Machine.slot(8)
    Libc.pipe(fds)
    read_end = zr_fix(Machine.u32(Machine.load32(fds, 0)))
    write_end = zr_fix(Machine.u32(Machine.load32(fds, 4)))
    zr_io_cloexec(read_end)
    zr_io_cloexec(write_end)
    zr_io_set_nonblock(read_end, zr_fix(1))
    zr_io_set_nonblock(write_end, zr_fix(1))
    Gvl[g].wake_r = zr_fix2long(read_end)
    Gvl[g].wake_w = zr_fix2long(write_end)
    old = Machine.slot(16)
    zr_os_sigaction(Machine.i32(SIGNAL_VTALRM), Machine.word(Machine.addr(:zr_trap_dropped)), old)
    g
  end

  # The state of the thread that runs a region on this OS thread, or 0:
  # C without the GVL asks (rb_thread_call_with_gvl, ruby_thread_has_gvl_p).
  any_thread :zr_region_self

  #: () -> ptr
  def zr_region_self
    g = Machine.static(:gvl, Gvl.size)
    if Gvl[g].mutex == 0
      return Machine.ptr(0)
    end
    Libc.pthread_getspecific(Gvl[g].key)
  end

  # rb_thread_call_without_gvl with native threads: `fn(data)` runs on
  # this thread's OS thread while another thread holds the GVL. An
  # interrupt that waits for a blocking call arrives first; one that
  # comes meanwhile calls `ubf(ubf_data)`, and arrives after.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def zr_region_call(fn, data, ubf, ubf_data)
    out = Machine.slot(8)
    if !zr_region_run(fn, data, ubf, ubf_data, out)
      zr_c_unwind()
    end
    Machine.ptr(Machine.load64(out, 0))
  end

  # `fn(data)` in a region, its result into `out`. False when an
  # interrupt raised, before the call or after it: the task's pending
  # unwind.
  #: (ptr, ptr, ptr, ptr, ptr) -> bool
  def zr_region_run(fn, data, ubf, ubf_data, out)
    thread = zr_core_class(Machine.id(:Thread))
    if zr_send(thread, Machine.id(:blocking_point), 0, Machine.ptr(0)) == QUNDEF
      return false
    end
    cur = zr_fiber_current()
    me = zr_thread_state(RFiber[cur].home, true)
    zr_region_release(me, Machine.word(cur), zr_region_plan(), ubf, ubf_data)
    Machine.store64(out, 0, zr_gc_call(fn, data, Machine.ptr(0)))
    # Only defs with no root frame run until the GVL is back: a root
    # frame's link and unlink write the holder's kernel root chain.
    if ThreadState[me].region != 0
      took = zr_region_take(me)
      zr_gvl_enter(Machine.word(cur))
      zr_gates_reload()
      if zr_region_left(cur, took, true) == QUNDEF
        return false
      end
    end
    true
  end

  # Where the GVL goes for a region (Thread.region_enter): 0 when this
  # thread keeps it, 1 when it goes free, else the state of the thread to
  # hand it to.
  #: () -> ptr
  def zr_region_plan
    to = zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:region_enter), 0, Machine.ptr(0))
    if to == QNIL || to == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      return Machine.ptr(0)
    end
    if to == QFALSE
      return Machine.ptr(1)
    end
    # As zr_fiber_scheduler_switch readies the fiber it switches to.
    cur = zr_fiber_current()
    if Task[RFiber[cur].task].ractor != Task[RFiber[to].task].ractor
      zr_consts_changed()
    end
    zr_fiber_run_prepare(to, 0, 0)
    zr_thread_state(RFiber[to].home, false)
  end

  # Gives the GVL away as `plan` says, for C that runs in fiber `cur`.
  # From here until zr_region_take this OS thread touches neither the
  # kernel's state nor the heap.
  any_thread :zr_region_release

  #: (ptr, word, ptr, ptr, ptr) -> void
  def zr_region_release(me, cur, plan, ubf, ubf_data)
    if plan == 0
      return
    end
    g = zr_gvl()
    ThreadState[me].region = 1
    ThreadState[me].cur = cur
    ThreadState[me].ubf = ubf
    ThreadState[me].ubf_data = ubf_data
    RFiber[Machine.value(cur)].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    Libc.pthread_setspecific(Gvl[g].key, me)
    zr_signals_mask_region()
    if plan == 1
      Libc.pthread_mutex_lock(Gvl[g].mutex)
      Gvl[g].free = 1
      Libc.pthread_mutex_unlock(Gvl[g].mutex)
    else
      zr_gvl_give(plan)
    end
  end

  # The GVL is back after a region: the scheduler hears of it
  # (Thread.region_leave), and with `check` an interrupt that came
  # meanwhile arrives, as a raise.
  #: (value, bool, bool) -> value
  def zr_region_left(cur, took, check)
    argv = Machine.slot(24)
    Machine.store64(argv, 0, Machine.word(RFiber[cur].home))
    Machine.store64(argv, 8, Machine.word(zr_bool(took)))
    Machine.store64(argv, 16, Machine.word(zr_bool(check)))
    zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:region_leave), 3, argv)
  end

  # Takes the GVL while it is free, or joins the threads that came back
  # and waits for the switch that gives it to this one. Whether it was
  # free.
  any_thread :zr_region_take

  #: (ptr) -> bool
  def zr_region_take(me)
    g = zr_gvl()
    Libc.pthread_setspecific(Gvl[g].key, Machine.ptr(0))
    ThreadState[me].region = 0
    Libc.pthread_mutex_lock(Gvl[g].mutex)
    if Gvl[g].free != 0
      Gvl[g].free = 0
      Libc.pthread_mutex_unlock(Gvl[g].mutex)
      return true
    end
    ThreadState[me].back = Gvl[g].back
    Gvl[g].back = me
    Libc.pthread_mutex_unlock(Gvl[g].mutex)
    zr_poll_set()
    byte = Machine.slot(8)
    Machine.store8(byte, 0, Machine.i8(1))
    Libc.write(Machine.i32(Gvl[g].wake_w), byte, 1)
    zr_gvl_wait(me)
    false
  end

  # rb_thread_call_with_gvl from C that runs without it: the thread takes
  # the GVL for `fn(data)`, then gives it away again. Its frames until it
  # holds the GVL have no root frame, as in zr_region_call.
  any_thread :zr_region_with_gvl

  #: (ptr, ptr, ptr) -> ptr
  def zr_region_with_gvl(me, fn, data)
    cur = ThreadState[me].cur
    ubf = ThreadState[me].ubf
    ubf_data = ThreadState[me].ubf_data
    took = zr_region_take(me)
    zr_gvl_enter(cur)
    zr_gates_reload()
    r = zr_region_callback(cur, took, fn, data)
    zr_region_release(me, cur, zr_region_plan(), ubf, ubf_data)
    r
  end

  # `fn(data)` with the GVL, inside a region. Its error cannot go through
  # the C that runs without the GVL, so it is dropped.
  #: (word, bool, ptr, ptr) -> ptr
  def zr_region_callback(cur, took, fn, data)
    zr_region_left(Machine.value(cur), took, false)
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(data))
    r = zr_call_c(fn, argv, 1)
    if r == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      r = QNIL
    end
    Machine.ptr(r)
  end

  # The threads that came back from a region, by their root fibers, or nil
  # if none came. Empties the GVL's list and its pipe.
  #: () -> value
  def zr_gvl_returned
    g = Machine.static(:gvl, Gvl.size)
    if Gvl[g].mutex == 0
      return Machine.value(QNIL)
    end
    Libc.pthread_mutex_lock(Gvl[g].mutex)
    ts = Gvl[g].back
    Gvl[g].back = Machine.ptr(0)
    Libc.pthread_mutex_unlock(Gvl[g].mutex)
    buf = Machine.slot(64)
    while Machine.sword(Libc.read(Machine.i32(Gvl[g].wake_r), buf, 64)) > 0
    end
    if ts == 0
      return Machine.value(QNIL)
    end
    roots = zr_ary_new(0)
    while ts != 0
      zr_ary_push(roots, Machine.value(ThreadState[ts].fiber))
      ts = ThreadState[ts].back
    end
    roots
  end

  # The read end of the GVL's pipe, or nil before the first region.
  #: () -> value
  def zr_gvl_wake_fd
    g = Machine.static(:gvl, Gvl.size)
    Gvl[g].mutex == 0 ? Machine.value(QNIL) : zr_fix(Gvl[g].wake_r)
  end

  # The scheduler has no thread to run and nothing to watch while threads
  # run C without the GVL: the GVL goes free, and this thread waits for
  # its next turn, or ends if its thread has (`exiting`). False, with the
  # GVL kept, if a thread came back first.
  #: (value) -> value
  def zr_gvl_release_idle(exiting)
    g = zr_gvl()
    cur = zr_fiber_current()
    me = zr_thread_state(RFiber[cur].home, true)
    RFiber[cur].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    zr_signals_mask(true)
    if !zr_gvl_free_unless_back(g)
      zr_signals_mask(false)
      return Machine.value(QFALSE)
    end
    if exiting == QTRUE
      ThreadState[me].next = Machine.ptr(0)
      zr_switch(RFiber[cur].ctx, ThreadState[me].entry)
    end
    zr_gvl_wait(me)
    zr_gvl_enter(Machine.word(cur))
    zr_gates_reload()
    Machine.value(QTRUE)
  end

  any_thread :zr_gvl_free_unless_back

  #: (ptr) -> bool
  def zr_gvl_free_unless_back(g)
    Libc.pthread_mutex_lock(Gvl[g].mutex)
    if Gvl[g].back != 0
      Libc.pthread_mutex_unlock(Gvl[g].mutex)
      return false
    end
    Gvl[g].free = 1
    Libc.pthread_mutex_unlock(Gvl[g].mutex)
    true
  end

  # The scheduler's sleep until the first sleeper's deadline, `ns` from
  # now: false when it ends early, for a signal or a thread back from a
  # region.
  #: (value) -> value
  def zr_idle_sleep(ns)
    wake = zr_gvl_wake_fd()
    if wake == QNIL
      return zr_nanosleep(ns)
    end
    fds = zr_ary_new(1)
    zr_ary_push(fds, wake)
    events = zr_ary_new(1)
    zr_ary_push(events, zr_fix(WAIT_READABLE))
    ready = zr_io_wait_fds(fds, events, zr_fix((zr_fix2long(ns) + 999999) / 1000000))
    if ready == QUNDEF
      return ready
    end
    zr_bool(zr_special_p(ready) || zr_fix2long(zr_ary_at(ready, 0)) == 0)
  end

  # Thread#raise or #kill of a thread that runs C without the GVL: the
  # C's unblocking function stops it, or a signal ends its system call.
  #: (value) -> value
  def zr_region_unblock(root)
    ts = RFiber[root].native
    if ts == 0 || ThreadState[ts].region == 0
      return Machine.value(QNIL)
    end
    ubf = ThreadState[ts].ubf
    if ubf == Machine.ptr(UBF_SIGNAL)
      Libc.pthread_kill(Machine.ptr(ThreadState[ts].pthread), Machine.i32(SIGNAL_VTALRM))
    elsif ubf != 0
      argv = Machine.slot(64)
      Machine.store64(argv, 0, Machine.word(ThreadState[ts].ubf_data))
      zr_call_c_returned(ubf, argv, 1)
    end
    Machine.value(QNIL)
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

  # A thread in a region takes no asynchronous signal but SIGVTALRM, which
  # an interrupt sends to end its system call.
  any_thread :zr_signals_mask_region

  #: () -> void
  def zr_signals_mask_region
    set = Machine.slot(128)
    Libc.memset(set, Machine.i32(255), 128)
    zr_sigset_clear(set, SIGNAL_ILL)
    zr_sigset_clear(set, 5)
    zr_sigset_clear(set, SIGNAL_ABRT)
    zr_sigset_clear(set, 8)
    zr_sigset_clear(set, SIGNAL_BUS)
    zr_sigset_clear(set, SIGNAL_SEGV)
    zr_sigset_clear(set, SIGNAL_VTALRM)
    Libc.pthread_sigmask(Machine.i32(SIG_SETMASK), set, Machine.ptr(0))
  end

  any_thread :zr_sigset_clear

  #: (ptr, word) -> void
  def zr_sigset_clear(set, signo)
    at = set + ((signo - 1) >> 3)
    Machine.store8(at, 0, Machine.i8(Machine.u8(Machine.load8(at, 0)) & (255 - (1 << ((signo - 1) & 7)))))
  end
end
