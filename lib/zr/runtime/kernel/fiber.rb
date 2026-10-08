module Zr::Kern
  # Fibers. Each fiber has its own task and its own machine stack. The
  # zr_switch stub switches between fibers. The task of the current fiber
  # is the current task. Each fiber keeps its own kernel root list.

  class RFiber < Layout
    attr_reader :basic #: RBasic
    attr_accessor :task #: ptr
    attr_accessor :ctx #: ptr
    attr_accessor :stack #: ptr
    attr_accessor :kroots #: ptr
    attr_accessor :blk #: value
    attr_accessor :status #: word
    attr_accessor :prev #: value
    attr_accessor :resuming #: value
    attr_accessor :value #: value
    attr_accessor :yielding #: word
    attr_accessor :transferred #: word
    attr_accessor :home #: value
    attr_accessor :kw #: word
  end

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
    Task[t].top = 0
    Task[t].stack_limit = stack_limit
    Task[t].pending = Machine.value(QNIL)
    Task[t].pending_kind = PENDING_RAISE
    Task[t].serial = 0
    Task[t].errinfo = Machine.value(QNIL)
    Task[t].kw = 0
    Task[t].guards = Machine.value(QNIL)
    Task[t].catches = Machine.value(QNIL)
    Task[t].throw_tag = Machine.value(QNIL)
    Task[t].missing = 0
    Task[t].found = Machine.value(QNIL)
    Task[t].refine = Machine.value(QNIL)
    Task[t].ractor = 0
    Task[t].eval_using = 0
    Task[t].pending_from = 0
    Task[t].root_env = Machine.value(QNIL)
    Task[t].flip_flops = Machine.value(QNIL)
    Task[t].cframe = 0
  end

  # Ends the current task's ractor marking for a time, as a ractor's
  # require runs on the main ractor. Returns 1 when it was marked, else 0.
  #: () -> value
  def zr_ractor_leave_m
    t = zr_task()
    was = Task[t].ractor
    Task[t].ractor = 0
    zr_fix(was)
  end

  # Marks the current task as a ractor task. After this, the task refuses
  # the program's reads and writes of instance variables of a shareable
  # object, as CRuby refuses them outside the main ractor.
  #: () -> value
  def zr_ractor_enter_m
    Task[zr_task()].ractor = 1
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
      RFiber[f].task = Machine.static(:task, Task.size)
      RFiber[f].ctx = zr_xmalloc(CONTEXT_BYTES)
      RFiber[f].stack = 0
      RFiber[f].kroots = 0
      RFiber[f].blk = Machine.value(QNIL)
      RFiber[f].status = FIBER_RESUMED
      RFiber[f].prev = Machine.value(QNIL)
      RFiber[f].resuming = Machine.value(QNIL)
      RFiber[f].value = Machine.value(QNIL)
      RFiber[f].yielding = 0
      RFiber[f].transferred = 0
      RFiber[f].home = f
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
    RFiber[f].task = 0
    RFiber[f].ctx = 0
    RFiber[f].stack = 0
    RFiber[f].kroots = 0
    RFiber[f].blk = Machine.value(QNIL)
    RFiber[f].status = FIBER_CREATED
    RFiber[f].prev = Machine.value(QNIL)
    RFiber[f].resuming = Machine.value(QNIL)
    RFiber[f].value = Machine.value(QNIL)
    RFiber[f].yielding = 0
    RFiber[f].transferred = 0
    RFiber[f].kw = 0
    RFiber[f].home = Machine.value(QNIL)
    zr_fiber_register(f)
    f
  end

  # `Fiber#initialize`: gives an allocated fiber its block, a task, a
  # stack, and a context that starts at zr_fiber_start on the first
  # resume. A fiber can be initialized only once, as in fiber_t_alloc.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_make(recv, argc, argv, cref, blk)
    if RFiber[recv].ctx != 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("cannot initialize twice"), 23)
    end
    cur = zr_fiber_current()
    f = recv
    RFiber[f].blk = zr_block_proc(blk)
    RFiber[f].status = FIBER_CREATED
    RFiber[f].prev = Machine.value(QNIL)
    RFiber[f].resuming = Machine.value(QNIL)
    RFiber[f].value = Machine.value(QNIL)
    RFiber[f].yielding = 0
    RFiber[f].transferred = 0
    RFiber[f].kroots = 0
    # A fiber belongs to the thread that makes it: the thread of the
    # current fiber.
    RFiber[f].home = RFiber[cur].home
    stack = zr_os_stack_map(FIBER_STACK_BYTES)
    if stack == 0
      return zr_fiber_stack_error(zr_errno())
    end
    t = zr_xmalloc(Task.size)
    zr_task_init(t, stack + STACK_MARGIN)
    RFiber[f].task = t
    RFiber[f].stack = stack
    ctx = zr_xmalloc(CONTEXT_BYTES)
    zr_arch_context_start(ctx, Machine.addr(:zr_fiber_start), Machine.word(stack) + FIBER_STACK_BYTES)
    RFiber[f].ctx = ctx
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
    if Task[RFiber[from].task].ractor != Task[RFiber[to].task].ractor
      zr_consts_changed()
    end
    RFiber[from].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    Machine.store64(Machine.static(:current_fiber, 8), 0, Machine.word(to))
    Machine.store64(zr_current_task_slot(), 0, Machine.word(RFiber[to].task))
    Machine.store64(zr_kroots(), 0, Machine.word(RFiber[to].kroots))
    zr_switch(RFiber[from].ctx, RFiber[to].ctx)
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
    if RFiber[recv].ctx == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    cur = zr_fiber_current()
    if RFiber[recv].status == FIBER_TERMINATED
      return zr_fiber_error(Machine.bytes("attempt to resume a terminated fiber"), 36)
    end
    if recv == cur
      return zr_fiber_error(Machine.bytes("attempt to resume the current fiber"), 35)
    end
    if RFiber[recv].prev != QNIL
      return zr_fiber_error(Machine.bytes("attempt to resume a resumed fiber (double resume)"), 49)
    end
    if RFiber[recv].resuming != QNIL
      return zr_fiber_error(Machine.bytes("attempt to resume a resuming fiber"), 34)
    end
    # As ruby's fiber_resume_kw: a fiber that has started and is not in
    # Fiber.yield, a root fiber among them, is transferring.
    if RFiber[recv].transferred != 0 || (RFiber[recv].yielding == 0 && RFiber[recv].status != FIBER_CREATED)
      return zr_fiber_error(Machine.bytes("attempt to resume a transferring fiber"), 38)
    end
    if RFiber[recv].home != RFiber[cur].home
      return zr_fiber_error(Machine.bytes("fiber called across threads"), 27)
    end
    # The first resume's keywords reach the block as keywords; a later
    # resume's arrive as a Hash, the value of Fiber.yield.
    if kw > 1
      argc = zr_kw_tab_in(kw, argc, argv)
      kw = zr_kw_hashed(kw)
    end
    if RFiber[recv].status == FIBER_CREATED
      RFiber[recv].kw = kw
    end
    RFiber[recv].prev = cur
    RFiber[cur].resuming = recv
    RFiber[recv].yielding = 0
    zr_trace_fiber_switched(zr_fiber_run(cur, recv, argc, argv), recv, Machine.id(:resume))
  end

  # `transfer(*args)`: moves control to the fiber. Only another transfer
  # moves control back. When the fiber ends, control goes to the deepest
  # fiber that the root fiber resumes.
  #: (value, word, ptr, value, value) -> value
  def zr_fiber_transfer(recv, argc, argv, cref, blk)
    if RFiber[recv].ctx == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    cur = zr_fiber_current()
    if RFiber[recv].resuming != QNIL
      return zr_fiber_error(Machine.bytes("attempt to transfer to a resuming fiber"), 39)
    end
    if RFiber[recv].yielding != 0
      return zr_fiber_error(Machine.bytes("attempt to transfer to a yielding fiber"), 39)
    end
    if RFiber[recv].status == FIBER_TERMINATED
      return zr_fiber_error(Machine.bytes("dead fiber called"), 17)
    end
    if recv == cur
      return zr_fiber_transfer_value(argc, argv)
    end
    if RFiber[recv].home != RFiber[cur].home
      return zr_fiber_error(Machine.bytes("fiber called across threads"), 27)
    end
    RFiber[cur].transferred = 1
    RFiber[cur].status = FIBER_SUSPENDED
    zr_trace_fiber_switched(zr_fiber_run(cur, recv, argc, argv), recv, Machine.id(:transfer))
  end

  # Gives `argc` arguments to `to` and runs it until control comes back to
  # `from`. Returns the value, or QUNDEF with the pending unwind.
  #: (value, value, word, ptr) -> value
  def zr_fiber_run(from, to, argc, argv)
    if RFiber[to].status == FIBER_CREATED
      RFiber[to].value = zr_ary_of(argc, argv)
    else
      RFiber[to].value = zr_fiber_transfer_value(argc, argv)
    end
    RFiber[to].status = FIBER_RESUMED
    # A fiber that runs again no longer waits as a transfer left it.
    RFiber[to].transferred = 0
    zr_fiber_switch(from, to)
    v = RFiber[from].value
    RFiber[from].value = Machine.value(QNIL)
    v
  end

  # Returns the fiber that gets control when the current fiber yields or
  # ends: its resumer, or else the deepest fiber that the root fiber resumes.
  #: (value, word) -> value
  def zr_fiber_return_to(cur, terminating)
    prev = RFiber[cur].prev
    if prev != QNIL
      RFiber[cur].prev = Machine.value(QNIL)
      RFiber[prev].resuming = Machine.value(QNIL)
      return prev
    end
    if terminating == 0
      return zr_fiber_error(Machine.bytes("attempt to yield on a not resumed fiber"), 39)
    end
    # A transferred fiber that ends goes back to the root fiber of its
    # thread, as CRuby's return_fiber does.
    f = RFiber[cur].home
    if f == QNIL
      f = zr_fiber_root()
    end
    while RFiber[f].resuming != QNIL
      f = RFiber[f].resuming
    end
    RFiber[f].transferred = 0
    f
  end

  # In a forked child, the fiber that forked is the root fiber, as
  # rb_fiber_atfork makes it: a transferred fiber that ends, there or in a
  # fiber it makes, comes back to it, and it has no resumer of its own.
  #: () -> value
  def zr_fiber_after_fork
    f = zr_fiber_current()
    RFiber[f].home = f
    RFiber[f].prev = Machine.value(QNIL)
    RFiber[f].transferred = 0
    Machine.store64(Machine.static(:root_fiber, 8), 0, Machine.word(f))
    Machine.value(QNIL)
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
    RFiber[to].value = zr_fiber_transfer_value(argc, argv)
    RFiber[cur].status = FIBER_SUSPENDED
    RFiber[cur].yielding = 1
    RFiber[to].status = FIBER_RESUMED
    zr_fiber_switch(cur, to)
    RFiber[cur].yielding = 0
    v = RFiber[cur].value
    RFiber[cur].value = Machine.value(QNIL)
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
    if RFiber[cur].home != cur
      r = zr_trace_fiber_switch(Machine.value(QNIL), 0)
    end
    if r != QUNDEF
      args = RFiber[cur].value
      Task[zr_task()].kw = RFiber[cur].kw
      RFiber[cur].kw = 0
      r = zr_yield(RFiber[cur].blk, RArray[args].len, RArray[args].ptr)
    end
    to = zr_fiber_return_to(cur, 1)
    # In a forked child the fiber that forked is the root of its thread
    # (zr_fiber_after_fork). When it ends, the program ends, as the end of
    # CRuby's root fiber ends the main thread.
    if to == cur
      exc = Machine.value(QNIL)
      if r == QUNDEF
        exc = Task[zr_task()].pending
        Task[zr_task()].pending = Machine.value(QNIL)
      end
      zr_proc_child_exit(exc)
    end
    if r == QUNDEF
      t = zr_task()
      Task[RFiber[to].task].pending = Task[t].pending
      Task[RFiber[to].task].pending_kind = Task[t].pending_kind
      Task[RFiber[to].task].pending_home = Task[t].pending_home
      Task[RFiber[to].task].pending_site = Task[t].pending_site
      Task[t].pending = Machine.value(QNIL)
    end
    RFiber[to].value = r
    RFiber[cur].status = FIBER_TERMINATED
    RFiber[to].status = FIBER_RESUMED
    zr_fiber_switch(cur, to)
    zr_bug(Machine.bytes("a terminated fiber ran again\n"), 29)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_fiber_alive_p(recv, argc, argv, cref, blk)
    if RFiber[recv].ctx == 0
      return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
    end
    zr_bool(RFiber[recv].status != FIBER_TERMINATED)
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
    status = RFiber[recv].resuming != QNIL ? FIBER_SUSPENDED : RFiber[recv].status
    if status == FIBER_CREATED
      zr_buf_push(b, Machine.bytes(" (created"), 9)
    elsif status == FIBER_RESUMED
      zr_buf_push(b, Machine.bytes(" (resumed"), 9)
    elsif status == FIBER_SUSPENDED
      zr_buf_push(b, Machine.bytes(" (suspended"), 11)
    else
      zr_buf_push(b, Machine.bytes(" (terminated"), 12)
    end
    if RFiber[recv].resuming != QNIL
      zr_buf_push(b, Machine.bytes(" by resuming"), 12)
    end
    zr_buf_push(b, Machine.bytes(")>"), 2)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # Returns the fiber that `recv` resumed and waits for, or nil.
  #: (value) -> value
  def zr_fiber_resuming_m(recv)
    RFiber[recv].resuming
  end

  # Returns the fiber that resumed `recv` and waits for it, or nil.
  #: (value) -> value
  def zr_fiber_prev_m(recv)
    RFiber[recv].prev
  end

  # Whether the fiber stopped because it transferred away, not because it
  # yielded or resumed another fiber (FIBER_SUSPENDED_P without yielding).
  #: (value) -> value
  def zr_fiber_transferred_away_p(recv)
    zr_bool(RFiber[recv].status == FIBER_SUSPENDED && RFiber[recv].yielding == 0 && RFiber[recv].resuming == QNIL)
  end

  # Whether the fiber has not run yet: its block waits for a first resume.
  #: (value) -> value
  def zr_fiber_unborn_p(recv)
    zr_bool(RFiber[recv].status == FIBER_CREATED)
  end

  # Ends a fiber that has not run yet. The kill runs no block and leaves
  # no stack to return to.
  #: (value) -> value
  def zr_fiber_terminate(recv)
    if RFiber[recv].status == FIBER_CREATED
      RFiber[recv].status = FIBER_TERMINATED
    end
    recv
  end

  # Makes the fiber the root of its own thread. It belongs to no other
  # thread, and each fiber that it makes belongs to the same thread.
  #: (value) -> value
  def zr_fiber_rehome(recv)
    RFiber[recv].home = recv
    recv
  end

  # Marks the references of a fiber object. The frame list, the task
  # slots and the kernel records on its stack are marked by
  # `zr_mark_fibers`.
  #: (value) -> void
  def zr_mark_fiber(f)
    zr_mark(RFiber[f].blk)
    zr_mark(RFiber[f].prev)
    zr_mark(RFiber[f].resuming)
    zr_mark(RFiber[f].value)
    zr_mark(RFiber[f].home)
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
  class FiberList < Layout
    attr_accessor :ptr #: ptr
    attr_accessor :len #: word
    attr_accessor :capa #: word
  end

  #: () -> ptr
  def zr_fiber_list
    Machine.static(:fiber_list, FiberList.size)
  end

  #: (value) -> void
  def zr_fiber_register(f)
    l = zr_fiber_list()
    n = FiberList[l].len
    if n == FiberList[l].capa
      capa = n == 0 ? 8 : n * 2
      grown = zr_xmalloc(capa * 8)
      if n > 0
        zr_memcpy(grown, FiberList[l].ptr, n * 8)
        zr_sized_xfree(FiberList[l].ptr, n * 8)
      end
      FiberList[l].ptr = grown
      FiberList[l].capa = capa
    end
    Machine.store64(FiberList[l].ptr + (n * 8), 0, Machine.word(f))
    FiberList[l].len = n + 1
  end

  # Marks the stacks of the live fibers, and repeats until no more fibers
  # become marked. The low bit of an entry's address (a cell address never
  # has it) records that its stack was read in this collection.
  #
  # This skips the fiber that runs now: `zr_mark_roots` marks its task,
  # and its kernel roots are the live root list, not the copy in the fiber.
  #: () -> void
  def zr_mark_fibers
    # @type var at: ptr
    l = zr_fiber_list()
    n = FiberList[l].len
    i = 0
    while i < n
      at = FiberList[l].ptr + (i * 8)
      Machine.store64(at, 0, Machine.load64(at, 0) & (0 - 2))
      i += 1
    end
    more = true
    while more
      more = false # rubocop:disable Lint/UselessAssignment -- the outer `while` reads it
      i = 0
      while i < FiberList[l].len
        at = FiberList[l].ptr + (i * 8)
        w = Machine.load64(at, 0)
        if (w & 1) == 0 && zr_marked_p(Machine.value(w))
          Machine.store64(at, 0, w | 1)
          more = true
          if RFiber[Machine.value(w)].task != 0 && w != Machine.load64(Machine.static(:current_fiber, 8), 0)
            zr_mark_task(RFiber[Machine.value(w)].task)
            zr_mark_kernel_roots_from(RFiber[Machine.value(w)].kroots)
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
    n = FiberList[l].len
    i = 0
    kept = 0
    while i < n
      f = Machine.value(Machine.load64(FiberList[l].ptr + (i * 8), 0) & (0 - 2))
      if zr_marked_p(f)
        Machine.store64(FiberList[l].ptr + (kept * 8), 0, Machine.word(f))
        kept += 1
      end
      i += 1
    end
    FiberList[l].len = kept
  end

  #: (value) -> void
  def zr_release_fiber(f)
    zr_xfree(RFiber[f].ctx)
    if RFiber[f].stack != 0
      Libc.munmap(RFiber[f].stack, FIBER_STACK_BYTES)
      zr_xfree(RFiber[f].task)
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
