module Zr::Kern
  # Fibers. Each fiber has its own task and its own machine stack. The
  # zr_switch stub switches between fibers. The task of the current fiber
  # is the current task. Each fiber keeps its own kernel root list.
  Libc.import :munmap, [Ptr, Word] => I32

  RFiber = layout basic: RBasic, task: Ptr, ctx: Ptr, stack: Ptr, kroots: Ptr, blk: Value, status: Word, prev: Value, resuming: Value, value: Value, yielding: Word, transferred: Word, home: Value, kw: Word
  T_FIBER = 30
  G_FIBER = 39
  FIBER_CREATED = 0
  FIBER_RESUMED = 1
  FIBER_SUSPENDED = 2
  FIBER_TERMINATED = 3
  # The size of the machine stack of a task. Ruby frames are native
  # frames here, so the stack must have space for the depth that ruby
  # gets on its VM stack. 10,000 frames of a plain method use about
  # 36 MiB. The system maps the pages only when the stack grows into them.
  FIBER_STACK_BYTES = 67108864

  # `can't allocate fiber stack: <strerror>`, as CRuby raises it.
  #: (word) -> value
  def zr_fiber_stack_error(err)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("can't allocate fiber stack: "), 28)
    text = Libc.strerror(Machine.i32(err))
    zr_buf_push(b, text, zr_cstr_len(text))
    zr_raise_buf(zr_core_class(Machine.id(:FiberError)), b)
  end

  # The task word and the preemption poll word (send.rb) are in one
  # static, so a compiled function reads both from one address.
  #: () -> ptr
  def zr_current_task_slot
    Machine.static(:current_task, 16)
  end

  #: () -> ptr
  def zr_poll_slot
    Machine.static(:current_task, 16) + 8
  end

  #: () -> ptr
  def zr_task
    Machine.ptr(Machine.load64(zr_current_task_slot(), 0))
  end

  # Sets up a task with the stack limit for its stack checks. Zero means
  # no check, as under wasm, where the stack bounds are not known.
  #: (ptr, ptr) -> void
  def zr_task_init(t, stack_limit)
    Task.set_top(t, 0)
    Task.set_stack_limit(t, stack_limit)
    Task.set_pending(t, Machine.value(QNIL))
    Task.set_pending_kind(t, PENDING_RAISE)
    Task.set_serial(t, 0)
    Task.set_errinfo(t, Machine.value(QNIL))
    Task.set_kw(t, 0)
    Task.set_guards(t, Machine.value(QNIL))
    Task.set_catches(t, Machine.value(QNIL))
    Task.set_throw_tag(t, Machine.value(QNIL))
    Task.set_missing(t, 0)
    Task.set_found(t, Machine.value(QNIL))
    Task.set_refine(t, Machine.value(QNIL))
    Task.set_ractor(t, 0)
  end

  # Marks the current task as a ractor task. After this, the task refuses
  # the program's reads and writes of instance variables of a shareable
  # object, as CRuby refuses them outside the main ractor.
  #: () -> value
  def zr_ractor_enter_m
    Task.set_ractor(zr_task(), 1)
    Machine.gates_set(Machine.gates | GATE_RACTOR)
    # Each constant read in a ractor checks whether it can share the
    # value, so no cache entry that the main ractor filled can be used.
    zr_consts_changed()
    Machine.value(QNIL)
  end

  # Returns the fiber that runs now. The root fiber represents the main task.
  #: () -> value
  def zr_fiber_current
    slot = Machine.static(:current_fiber, 8)
    f = Machine.value(Machine.load64(slot, 0))
    if zr_special_p(f)
      f = zr_alloc(T_FIBER, zr_global(G_FIBER), RFiber.size)
      RFiber.set_task(f, Machine.static(:task, Task.size))
      RFiber.set_ctx(f, zr_xmalloc(CONTEXT_BYTES))
      RFiber.set_stack(f, 0)
      RFiber.set_kroots(f, 0)
      RFiber.set_blk(f, Machine.value(QNIL))
      RFiber.set_status(f, FIBER_RESUMED)
      RFiber.set_prev(f, Machine.value(QNIL))
      RFiber.set_resuming(f, Machine.value(QNIL))
      RFiber.set_value(f, Machine.value(QNIL))
      RFiber.set_yielding(f, 0)
      RFiber.set_transferred(f, 0)
      RFiber.set_home(f, f)
      zr_fiber_register(f)
      Machine.store64(slot, 0, Machine.word(f))
      Machine.store64(Machine.static(:root_fiber, 8), 0, Machine.word(f))
    end
    f
  end

  #: (value, word, ptr, value, value) -> value
  def zr_fiber_current_m(recv, argc, argv, cref, blk)
    zr_fiber_current()
  end

  # `Fiber.allocate`: a fiber that is not initialized. It has no block, no
  # context, no stack and no task, and it refuses to run.
  #: (value) -> value
  def zr_fiber_alloc(klass)
    f = zr_alloc(T_FIBER, klass, RFiber.size)
    RFiber.set_task(f, 0)
    RFiber.set_ctx(f, 0)
    RFiber.set_stack(f, 0)
    RFiber.set_kroots(f, 0)
    RFiber.set_blk(f, Machine.value(QNIL))
    RFiber.set_status(f, FIBER_CREATED)
    RFiber.set_prev(f, Machine.value(QNIL))
    RFiber.set_resuming(f, Machine.value(QNIL))
    RFiber.set_value(f, Machine.value(QNIL))
    RFiber.set_yielding(f, 0)
    RFiber.set_transferred(f, 0)
    RFiber.set_kw(f, 0)
    RFiber.set_home(f, Machine.value(QNIL))
    zr_fiber_register(f)
    f
  end

  # `Fiber#initialize`: gives an allocated fiber its block, a task, a
  # stack, and a context that starts at zr_fiber_start on the first
  # resume. A fiber can be initialized only once, as in fiber_t_alloc.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_make(recv, argc, argv, cref, blk)
    if RFiber.ctx(recv) != 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("cannot initialize twice"), 23)
    end
    cur = zr_fiber_current()
    f = recv
    RFiber.set_blk(f, zr_block_proc(blk))
    RFiber.set_status(f, FIBER_CREATED)
    RFiber.set_prev(f, Machine.value(QNIL))
    RFiber.set_resuming(f, Machine.value(QNIL))
    RFiber.set_value(f, Machine.value(QNIL))
    RFiber.set_yielding(f, 0)
    RFiber.set_transferred(f, 0)
    RFiber.set_kroots(f, 0)
    # A fiber belongs to the thread that makes it: the thread of the
    # current fiber.
    RFiber.set_home(f, RFiber.home(cur))
    stack = zr_os_stack_map(FIBER_STACK_BYTES)
    if stack == 0
      return zr_fiber_stack_error(zr_errno())
    end
    t = zr_xmalloc(Task.size)
    zr_task_init(t, stack + STACK_MARGIN)
    RFiber.set_task(f, t)
    RFiber.set_stack(f, stack)
    ctx = zr_xmalloc(CONTEXT_BYTES)
    zr_arch_context_start(ctx, Machine.addr(:zr_fiber_start), Machine.word(stack) + FIBER_STACK_BYTES)
    RFiber.set_ctx(f, ctx)
    f
  end

  # Returns the value that `argc` arguments give across a switch: nil for
  # zero, the argument for one, or an Array of all of them.
  #: (word, ptr) -> value
  def zr_fiber_transfer_value(argc, argv)
    if argc == 0
      return Machine.value(QNIL)
    end
    if argc == 1
      return Machine.value(Machine.load64(argv, 0))
    end
    zr_ary_of(argc, argv)
  end

  # Switches from `from` to `to`. It first changes the statics that
  # identify the running fiber. They change back when `from` runs again.
  #: (value, value) -> void
  def zr_fiber_switch(from, to)
    # A switch into or out of a ractor task makes the constant cache
    # entries stale: a ractor's reads check each value, and the main
    # ractor's reads fill the cache entries again.
    if Task.ractor(RFiber.task(from)) != Task.ractor(RFiber.task(to))
      zr_consts_changed()
    end
    RFiber.set_kroots(from, Machine.ptr(Machine.load64(zr_kroots(), 0)))
    Machine.store64(Machine.static(:current_fiber, 8), 0, Machine.word(to))
    Machine.store64(zr_current_task_slot(), 0, Machine.word(RFiber.task(to)))
    Machine.store64(zr_kroots(), 0, Machine.word(RFiber.kroots(to)))
    zr_switch(RFiber.ctx(from), RFiber.ctx(to))
  end

  #: (ptr, word) -> value
  def zr_fiber_error(bytes, len)
    zr_raise_msg(zr_core_class(Machine.id(:FiberError)), bytes, len)
  end

  # `resume(*args)`: runs the fiber until it yields or ends. Returns the
  # value that it yields or returns, or QUNDEF with its pending unwind.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_resume(recv, argc, argv, cref, blk)
    kw = zr_kw_take()
    if RFiber.ctx(recv) == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    cur = zr_fiber_current()
    if RFiber.status(recv) == FIBER_TERMINATED
      return zr_fiber_error(Machine.bytes("attempt to resume a terminated fiber"), 36)
    end
    if recv == cur
      return zr_fiber_error(Machine.bytes("attempt to resume the current fiber"), 35)
    end
    if RFiber.prev(recv) != QNIL
      return zr_fiber_error(Machine.bytes("attempt to resume a resumed fiber (double resume)"), 49)
    end
    if RFiber.resuming(recv) != QNIL
      return zr_fiber_error(Machine.bytes("attempt to resume a resuming fiber"), 34)
    end
    # As ruby's fiber_resume_kw: a fiber that has started and is not in
    # Fiber.yield, a root fiber among them, is transferring.
    if RFiber.transferred(recv) != 0 || (RFiber.yielding(recv) == 0 && RFiber.status(recv) != FIBER_CREATED)
      return zr_fiber_error(Machine.bytes("attempt to resume a transferring fiber"), 38)
    end
    if RFiber.home(recv) != RFiber.home(cur)
      return zr_fiber_error(Machine.bytes("fiber called across threads"), 27)
    end
    # The first resume's keywords reach the block as keywords; a later
    # resume's arrive as a Hash, the value of Fiber.yield.
    if kw > 1
      argc = zr_kw_tab_in(kw, argc, argv)
      kw = zr_kw_hashed(kw)
    end
    if RFiber.status(recv) == FIBER_CREATED
      RFiber.set_kw(recv, kw)
    end
    RFiber.set_prev(recv, cur)
    RFiber.set_resuming(cur, recv)
    RFiber.set_yielding(recv, 0)
    zr_trace_fiber_switched(zr_fiber_run(cur, recv, argc, argv), recv, Machine.id(:resume))
  end

  # `transfer(*args)`: moves control to the fiber. Only another transfer
  # moves control back. When the fiber ends, control goes to the deepest
  # fiber that the root fiber resumes.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_transfer(recv, argc, argv, cref, blk)
    if RFiber.ctx(recv) == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    cur = zr_fiber_current()
    if RFiber.resuming(recv) != QNIL
      return zr_fiber_error(Machine.bytes("attempt to transfer to a resuming fiber"), 39)
    end
    if RFiber.yielding(recv) != 0
      return zr_fiber_error(Machine.bytes("attempt to transfer to a yielding fiber"), 39)
    end
    if RFiber.status(recv) == FIBER_TERMINATED
      return zr_fiber_error(Machine.bytes("dead fiber called"), 17)
    end
    if recv == cur
      return zr_fiber_transfer_value(argc, argv)
    end
    if RFiber.home(recv) != RFiber.home(cur)
      return zr_fiber_error(Machine.bytes("fiber called across threads"), 27)
    end
    RFiber.set_transferred(cur, 1)
    RFiber.set_status(cur, FIBER_SUSPENDED)
    zr_trace_fiber_switched(zr_fiber_run(cur, recv, argc, argv), recv, Machine.id(:transfer))
  end

  # Gives `argc` arguments to `to` and runs it until control comes back to
  # `from`. Returns the value, or QUNDEF with the pending unwind.
  #: (value, value, word, ptr) -> value
  def zr_fiber_run(from, to, argc, argv)
    if RFiber.status(to) == FIBER_CREATED
      RFiber.set_value(to, zr_ary_of(argc, argv))
    else
      RFiber.set_value(to, zr_fiber_transfer_value(argc, argv))
    end
    RFiber.set_status(to, FIBER_RESUMED)
    zr_fiber_switch(from, to)
    v = RFiber.value(from)
    RFiber.set_value(from, Machine.value(QNIL))
    v
  end

  # Returns the fiber that gets control when the current fiber yields or
  # ends: its resumer, or else the deepest fiber that the root fiber resumes.
  #: (value, word) -> value
  def zr_fiber_return_to(cur, terminating)
    prev = RFiber.prev(cur)
    if prev != QNIL
      RFiber.set_prev(cur, Machine.value(QNIL))
      RFiber.set_resuming(prev, Machine.value(QNIL))
      return prev
    end
    if terminating == 0
      return zr_fiber_error(Machine.bytes("attempt to yield on a not resumed fiber"), 39)
    end
    # A transferred fiber that ends goes back to the root fiber of its
    # thread, as CRuby's return_fiber does.
    f = RFiber.home(cur)
    if f == QNIL
      f = zr_fiber_root()
    end
    while RFiber.resuming(f) != QNIL
      f = RFiber.resuming(f)
    end
    f
  end

  #: () -> value
  def zr_fiber_root
    Machine.value(Machine.load64(Machine.static(:root_fiber, 8), 0))
  end

  # `Fiber.yield(*args)`: goes back to the resumer with a value. Returns
  # the value of the next resume.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_yield(recv, argc, argv, cref, blk)
    cur = zr_fiber_current()
    to = zr_fiber_return_to(cur, 0)
    if to == QUNDEF
      return Machine.value(QUNDEF)
    end
    RFiber.set_value(to, zr_fiber_transfer_value(argc, argv))
    RFiber.set_status(cur, FIBER_SUSPENDED)
    RFiber.set_yielding(cur, 1)
    RFiber.set_status(to, FIBER_RESUMED)
    zr_fiber_switch(cur, to)
    RFiber.set_yielding(cur, 0)
    v = RFiber.value(cur)
    RFiber.set_value(cur, Machine.value(QNIL))
    zr_trace_fiber_switched(v, recv, Machine.id(:yield))
  end

  # The entry point of a new fiber. It calls the block with the arguments
  # of the first resume. When the block ends, its value or its pending
  # unwind goes to the next fiber. Control never comes back to this stack.
  #: () -> void
  def zr_fiber_start
    cur = zr_fiber_current()
    # A switch brought control here, as at the other three switch points,
    # so the fiber switch hook fires. A fiber that is the root of a thread
    # is not a program fiber, so a thread start fires no hook. If the hook
    # raises, the fiber ends with that exception, as a raise at the first
    # instruction of the block does.
    r = Machine.value(QNIL)
    if RFiber.home(cur) != cur
      r = zr_trace_fiber_switch(Machine.value(QNIL), 0)
    end
    if r != QUNDEF
      args = RFiber.value(cur)
      Task.set_kw(zr_task(), RFiber.kw(cur))
      RFiber.set_kw(cur, 0)
      r = zr_yield(RFiber.blk(cur), RArray.len(args), RArray.ptr(args))
    end
    to = zr_fiber_return_to(cur, 1)
    if r == QUNDEF
      t = zr_task()
      Task.set_pending(RFiber.task(to), Task.pending(t))
      Task.set_pending_kind(RFiber.task(to), Task.pending_kind(t))
      Task.set_pending_home(RFiber.task(to), Task.pending_home(t))
      Task.set_pending_site(RFiber.task(to), Task.pending_site(t))
      Task.set_pending(t, Machine.value(QNIL))
    end
    RFiber.set_value(to, r)
    RFiber.set_status(cur, FIBER_TERMINATED)
    RFiber.set_status(to, FIBER_RESUMED)
    zr_fiber_switch(cur, to)
    zr_bug(Machine.bytes("a terminated fiber ran again\n"), 29)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_fiber_alive_p(recv, argc, argv, cref, blk)
    if RFiber.ctx(recv) == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    zr_bool(RFiber.status(recv) != FIBER_TERMINATED)
  end

  # Returns `#<Fiber:0x... file:line (status)>`, as fiber_to_s writes it.
  # `blk` is the block that the program gave to Fiber.new, or nil for the
  # root fiber of a thread. A fiber that resumes another shows as
  # "suspended by resuming", because CRuby sets that status on the fiber
  # that it switches away from.
  #: (value, value) -> value
  def zr_fiber_inspect_m(recv, blk)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, recv)
    if blk != QNIL && !zr_buf_block_where(b, blk)
      zr_buf_free(b)
      return Machine.value(QUNDEF)
    end
    status = RFiber.resuming(recv) != QNIL ? FIBER_SUSPENDED : RFiber.status(recv)
    if status == FIBER_CREATED
      zr_buf_push(b, Machine.bytes(" (created"), 9)
    elsif status == FIBER_RESUMED
      zr_buf_push(b, Machine.bytes(" (resumed"), 9)
    elsif status == FIBER_SUSPENDED
      zr_buf_push(b, Machine.bytes(" (suspended"), 11)
    else
      zr_buf_push(b, Machine.bytes(" (terminated"), 12)
    end
    if RFiber.resuming(recv) != QNIL
      zr_buf_push(b, Machine.bytes(" by resuming"), 12)
    end
    zr_buf_push(b, Machine.bytes(")>"), 2)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # Returns the fiber that `recv` resumed and waits for, or nil.
  #: (value) -> value
  def zr_fiber_resuming_m(recv)
    RFiber.resuming(recv)
  end

  # Returns the fiber that resumed `recv` and waits for it, or nil.
  #: (value) -> value
  def zr_fiber_prev_m(recv)
    RFiber.prev(recv)
  end

  # Whether the fiber stopped because it transferred away, not because it
  # yielded or resumed another fiber (FIBER_SUSPENDED_P without yielding).
  #: (value) -> value
  def zr_fiber_transferred_away_p(recv)
    zr_bool(RFiber.status(recv) == FIBER_SUSPENDED && RFiber.yielding(recv) == 0 && RFiber.resuming(recv) == QNIL)
  end

  # Whether the fiber has not run yet: its block waits for a first resume.
  #: (value) -> value
  def zr_fiber_unborn_p(recv)
    zr_bool(RFiber.status(recv) == FIBER_CREATED)
  end

  # Ends a fiber that has not run yet. The kill runs no block and leaves
  # no stack to return to.
  #: (value) -> value
  def zr_fiber_terminate(recv)
    if RFiber.status(recv) == FIBER_CREATED
      RFiber.set_status(recv, FIBER_TERMINATED)
    end
    recv
  end

  # Makes the fiber the root of its own thread. It belongs to no other
  # thread, and each fiber that it makes belongs to the same thread.
  #: (value) -> value
  def zr_fiber_rehome(recv)
    RFiber.set_home(recv, recv)
    recv
  end

  # Marks the references of a fiber object. The frame list, the task
  # slots and the kernel records on its stack are marked by
  # `zr_mark_fibers`.
  #: (value) -> void
  def zr_mark_fiber(f)
    zr_mark(RFiber.blk(f))
    zr_mark(RFiber.prev(f))
    zr_mark(RFiber.resuming(f))
    zr_mark(RFiber.value(f))
    zr_mark(RFiber.home(f))
  end

  # A list of all fibers that the program makes, so that a collection can
  # read the frames and kernel roots of each live fiber.
  #
  # A stack is not a set of ordinary references. It changes with no store
  # that the write barrier sees, so a minor collection that stops at an
  # old fiber would sweep objects that only the stack refers to.
  #
  # CRuby solves this in two ways. A running thread is reachable from
  # `vm->ractor.set`, which is a root (vm.c, rb_vm_mark). A suspended
  # Fiber is wb-unprotected: `fiber_data_type` (cont.c:2049) does not set
  # `RUBY_TYPED_WB_PROTECTED`, so `gc_aging` (default.c:4390) never
  # promotes it, each minor collection traces it again, and
  # `rgengc_check_relation` remembers each old object that points to one.
  #
  # Here, one list does both. A collection marks the object graph. Then it
  # reads the stack of each fiber in this list that the graph reaches, and
  # repeats while that marks more. A fiber with no references is never
  # read and is swept as usual. A live fiber has its stack read, old or young.
  FiberList = layout ptr: Ptr, len: Word, capa: Word

  #: () -> ptr
  def zr_fiber_list
    Machine.static(:fiber_list, FiberList.size)
  end

  #: (value) -> void
  def zr_fiber_register(f)
    l = zr_fiber_list()
    n = FiberList.len(l)
    if n == FiberList.capa(l)
      capa = n == 0 ? 8 : n * 2
      grown = zr_xmalloc(capa * 8)
      if n > 0
        zr_memcpy(grown, FiberList.ptr(l), n * 8)
        zr_sized_xfree(FiberList.ptr(l), n * 8)
      end
      FiberList.set_ptr(l, grown)
      FiberList.set_capa(l, capa)
    end
    Machine.store64(FiberList.ptr(l) + (n * 8), 0, Machine.word(f))
    FiberList.set_len(l, n + 1)
  end

  # Marks the stacks of the live fibers, and repeats until no more fibers
  # become marked. The low bit of an entry's address (a cell address never
  # has it) records that its stack was read in this collection.
  #
  # This skips the fiber that runs now: `zr_mark_roots` marks its task,
  # and its kernel roots are the live root list, not the copy in the fiber.
  #: () -> void
  def zr_mark_fibers
    l = zr_fiber_list()
    n = FiberList.len(l)
    i = 0
    while i < n
      at = FiberList.ptr(l) + (i * 8)
      Machine.store64(at, 0, Machine.load64(at, 0) & (0 - 2))
      i += 1
    end
    more = true
    while more
      more = false # rubocop:disable Lint/UselessAssignment -- the outer `while` reads it
      i = 0
      while i < FiberList.len(l)
        at = FiberList.ptr(l) + (i * 8)
        w = Machine.load64(at, 0)
        if (w & 1) == 0 && zr_marked_p(Machine.value(w))
          Machine.store64(at, 0, w | 1)
          more = true
          if RFiber.task(Machine.value(w)) != 0 && w != Machine.load64(Machine.static(:current_fiber, 8), 0)
            zr_mark_task(RFiber.task(Machine.value(w)))
            zr_mark_kernel_roots_from(RFiber.kroots(Machine.value(w)))
            zr_mark_drain()
          end
        end
        i += 1
      end
    end
  end

  # Removes the entries of fibers that the collection did not mark, and
  # clears the read bits of the others. This runs with `zr_weak_prune`,
  # before the sweep frees the stack and the task of a dead fiber.
  #: () -> void
  def zr_fiber_prune
    l = zr_fiber_list()
    n = FiberList.len(l)
    i = 0
    kept = 0
    while i < n
      f = Machine.value(Machine.load64(FiberList.ptr(l) + (i * 8), 0) & (0 - 2))
      if zr_marked_p(f)
        Machine.store64(FiberList.ptr(l) + (kept * 8), 0, Machine.word(f))
        kept += 1
      end
      i += 1
    end
    FiberList.set_len(l, kept)
  end

  #: (value) -> void
  def zr_release_fiber(f)
    zr_xfree(RFiber.ctx(f))
    if RFiber.stack(f) != 0
      Libc.munmap(RFiber.stack(f), FIBER_STACK_BYTES)
      zr_xfree(RFiber.task(f))
    end
  end

  # The switch for the thread scheduler. It moves control to `to` with no
  # checks and sets no flag, so both fibers keep their resume and
  # transfer state.
  #: (value) -> value
  def zr_fiber_scheduler_switch(to)
    cur = zr_fiber_current()
    if to == cur
      return Machine.value(QNIL)
    end
    zr_fiber_run(cur, to, 0, 0)
  end
end
