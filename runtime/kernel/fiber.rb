# Fibers: each one a task of its own on a machine stack of its own,
# switched with the zr_switch stub. The current fiber's task is the
# task; the kernel root chain travels with the fiber.
Machine.import "munmap", [Ptr, Word] => I32

Machine.struct :RFiber, basic: RBasic, task: Ptr, ctx: Ptr, stack: Ptr, kroots: Ptr, blk: Value, status: Word, prev: Value, resuming: Value, value: Value, yielding: Word, transferred: Word, home: Value
T_FIBER = 30
G_FIBER = 39
FIBER_CREATED = 0
FIBER_RESUMED = 1
FIBER_SUSPENDED = 2
FIBER_TERMINATED = 3
# A task's own machine stack. Ruby frames are native frames here, so
# the depth ruby reaches on its VM stack needs room: 10,000 frames of
# a plain method measure about 36 MiB. The pages arrive only as the
# stack grows into them.
FIBER_STACK_BYTES = 67108864

# `can't allocate fiber stack: <strerror>`, as CRuby raises it.
sig [Word] => Value
machine def zr_fiber_stack_error(err)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("can't allocate fiber stack: "), 28)
  text = strerror(Machine.i32(err))
  zr_buf_push(b, text, zr_cstr_len(text))
  zr_raise_buf(zr_core_class(Machine.id(:FiberError)), b)
end

sig [] => Ptr
# The task word and the preemption's poll word (send.rb) share one
# static, so a compiled function reads both off the one address.
machine def zr_current_task_slot
  Machine.static(:current_task, 16)
end

sig [] => Ptr
machine def zr_poll_slot
  Machine.static(:current_task, 16) + 8
end

sig [] => Ptr
machine def zr_task
  Machine.ptr(Machine.load64(zr_current_task_slot(), 0))
end

# A task starts with the stack limit its checks compare against: zero
# means no check, as under wasm, where the stack's bounds are unknown.
sig [Ptr, Ptr] => Void
machine def zr_task_init(t, stack_limit)
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

# This task is a ractor's own from here on, so the program's reads and
# writes of a shareable object's instance variables are refused in it, as
# CRuby refuses them outside the main ractor.
sig [] => Value
machine def zr_ractor_enter_m
  Task.set_ractor(zr_task(), 1)
  # A ractor's constant reads each ask whether it may share the value,
  # so no cell the main ractor filled may answer them.
  zr_consts_changed()
  Machine.value(QNIL)
end

# The fiber running now; the root fiber stands for the main task.
sig [] => Value
machine def zr_fiber_current
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

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_current_m(recv, argc, argv, cref, blk)
  zr_fiber_current()
end

# `Fiber.allocate`: a fiber that was never made, with no block, no
# context, no stack and no task, which refuses to run.
sig [Value] => Value
machine def zr_fiber_alloc(klass)
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
  RFiber.set_home(f, Machine.value(QNIL))
  zr_fiber_register(f)
  f
end

# What `Fiber#initialize` makes of an allocated fiber: the block, a task
# and a stack, and a context that starts at zr_fiber_start when first
# resumed. A fiber is made once, as fiber_t_alloc allows.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_make(recv, argc, argv, cref, blk)
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
  # A fiber belongs to the thread that makes it, which is the thread
  # the fiber it is made on belongs to.
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

# The value `argc` arguments carry across a switch: nil, the one, or
# all of them.
sig [Word, Ptr] => Value
machine def zr_fiber_transfer_value(argc, argv)
  if argc == 0
    return Machine.value(QNIL)
  end
  if argc == 1
    return Machine.value(Machine.load64(argv, 0))
  end
  zr_ary_of(argc, argv)
end

# Leave `from` for `to`: the statics that name the running fiber move
# first, and come back when `from` runs again.
sig [Value, Value] => Void
machine def zr_fiber_switch(from, to)
  # Into or out of a ractor's task, the constant cells go stale: a
  # ractor's reads ask, and the main ractor's fill the cells again.
  if Task.ractor(RFiber.task(from)) != Task.ractor(RFiber.task(to))
    zr_consts_changed()
  end
  RFiber.set_kroots(from, Machine.ptr(Machine.load64(zr_kroots(), 0)))
  Machine.store64(Machine.static(:current_fiber, 8), 0, Machine.word(to))
  Machine.store64(zr_current_task_slot(), 0, Machine.word(RFiber.task(to)))
  Machine.store64(zr_kroots(), 0, Machine.word(RFiber.kroots(to)))
  zr_switch(RFiber.ctx(from), RFiber.ctx(to))
end

sig [Ptr, Word] => Value
machine def zr_fiber_error(bytes, len)
  zr_raise_msg(zr_core_class(Machine.id(:FiberError)), bytes, len)
end

# `resume(*args)`: the fiber runs until it yields or ends; its answer
# is the value it yielded or returned, or the signal it left pending.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_resume(recv, argc, argv, cref, blk)
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
  if RFiber.transferred(recv) != 0
    return zr_fiber_error(Machine.bytes("attempt to resume a transferring fiber"), 38)
  end
  if RFiber.home(recv) != RFiber.home(cur)
    return zr_fiber_error(Machine.bytes("fiber called across threads"), 27)
  end
  RFiber.set_prev(recv, cur)
  RFiber.set_resuming(cur, recv)
  RFiber.set_yielding(recv, 0)
  zr_trace_fiber_switched(zr_fiber_run(cur, recv, argc, argv), recv, Machine.id(:resume))
end

# `transfer(*args)`: control moves to the fiber with no way back but
# another transfer; when it ends, control returns to the root fiber's
# deepest resumed fiber.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_transfer(recv, argc, argv, cref, blk)
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

# Hand `argc` arguments to `to` and run it until control comes back to
# `from`; the answer is the value or the pending signal it left.
sig [Value, Value, Word, Ptr] => Value
machine def zr_fiber_run(from, to, argc, argv)
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

# Where control goes when the current fiber yields or ends: its
# resumer, else the deepest fiber the root fiber is resuming.
sig [Value, Word] => Value
machine def zr_fiber_return_to(cur, terminating)
  prev = RFiber.prev(cur)
  if prev != QNIL
    RFiber.set_prev(cur, Machine.value(QNIL))
    RFiber.set_resuming(prev, Machine.value(QNIL))
    return prev
  end
  if terminating == 0
    return zr_fiber_error(Machine.bytes("attempt to yield on a not resumed fiber"), 39)
  end
  # A transferred fiber that ends goes back to its thread's root fiber,
  # as CRuby's return_fiber takes the thread's root.
  f = RFiber.home(cur)
  if f == QNIL
    f = zr_fiber_root()
  end
  while RFiber.resuming(f) != QNIL
    f = RFiber.resuming(f)
  end
  f
end

sig [] => Value
machine def zr_fiber_root
  Machine.value(Machine.load64(Machine.static(:root_fiber, 8), 0))
end

# `Fiber.yield(*args)`: back to the resumer with a value; the next
# resume's value comes back.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_yield(recv, argc, argv, cref, blk)
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

# A fresh fiber's first instruction: the block with the first resume's
# arguments; when it ends, its value or its pending signal goes to the
# fiber control returns to, and the stack is never returned to.
sig [] => Void
machine def zr_fiber_start
  cur = zr_fiber_current()
  # Control arrived here by a switch, as it does at the other three
  # places. A fiber that heads a thread is that thread and not a fiber
  # of the program's, so a thread starting fires nothing. A handler
  # that raises ends the fiber with what it raised, which is what a
  # raise at the block's first instruction does.
  r = Machine.value(QNIL)
  if RFiber.home(cur) != cur
    r = zr_trace_fiber_switch(Machine.value(QNIL), 0)
  end
  if r != QUNDEF
    args = RFiber.value(cur)
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

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_alive_p(recv, argc, argv, cref, blk)
  if RFiber.ctx(recv) == 0
    return zr_fiber_error(Machine.bytes("uninitialized fiber"), 19)
  end
  zr_bool(RFiber.status(recv) != FIBER_TERMINATED)
end

# `#<Fiber:0x... file:line (status)>`, as fiber_to_s writes it, where
# `blk` is the block the program gave Fiber.new, or nil for a thread's
# own fiber. A fiber that resumed another is suspended "by resuming" it,
# as CRuby stores the status of the fiber it switches away from.
sig [Value, Value] => Value
machine def zr_fiber_inspect_m(recv, blk)
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

# The fiber `recv` resumed and waits on, or nil.
sig [Value] => Value
machine def zr_fiber_resuming_m(recv)
  RFiber.resuming(recv)
end

# Whether the fiber stopped by transferring away, rather than by
# yielding or resuming another, as FIBER_SUSPENDED_P without yielding.
sig [Value] => Value
machine def zr_fiber_transferred_away_p(recv)
  zr_bool(RFiber.status(recv) == FIBER_SUSPENDED && RFiber.yielding(recv) == 0 && RFiber.resuming(recv) == QNIL)
end

# Whether the fiber has never run: its block waits for a first resume.
sig [Value] => Value
machine def zr_fiber_unborn_p(recv)
  zr_bool(RFiber.status(recv) == FIBER_CREATED)
end

# A fiber that has never run ends where it stands: killing it runs no
# block and leaves no stack to return to.
sig [Value] => Value
machine def zr_fiber_terminate(recv)
  if RFiber.status(recv) == FIBER_CREATED
    RFiber.set_status(recv, FIBER_TERMINATED)
  end
  recv
end

# The fiber heads a thread of its own: it belongs to no other thread,
# and every fiber made on it belongs to the same thread.
sig [Value] => Value
machine def zr_fiber_rehome(recv)
  RFiber.set_home(recv, recv)
  recv
end

# A suspended fiber's roots: its frame chain, its task's slots, and the
# kernel records on its stack.
sig [Value] => Void
machine def zr_mark_fiber(f)
  zr_mark(RFiber.blk(f))
  zr_mark(RFiber.prev(f))
  zr_mark(RFiber.resuming(f))
  zr_mark(RFiber.value(f))
  zr_mark(RFiber.home(f))
end

# Every fiber the program has made, so that a collection can read the
# frames and the kernel roots of each one that is live.
#
# Those are a running stack and not ordinary references: they change
# with no store the write barrier could see, so a minor collection that
# stopped at an old fiber would sweep what the stack alone holds.
#
# CRuby answers the same problem twice. A running thread is reached from
# `vm->ractor.set`, which is a root (vm.c, rb_vm_mark); a suspended
# Fiber is **wb-unprotected** -- `fiber_data_type` (cont.c:2049) asks for
# no `RUBY_TYPED_WB_PROTECTED`, so `gc_aging` (default.c:4390) never
# promotes it and every minor collection traces it again, and
# `rgengc_check_relation` remembers any old object that points at one.
#
# One list does both here. A collection marks the object graph, then
# reads the stack of every fiber in this list the graph reached, and
# repeats while that reaches more. A fiber nothing refers to is never
# read and is swept like anything else; a fiber that is live has its
# stack read whether it is old or young.
Machine.struct :FiberList, ptr: Ptr, len: Word, capa: Word

sig [] => Ptr
machine def zr_fiber_list
  Machine.static(:fiber_list, FiberList.size)
end

sig [Value] => Void
machine def zr_fiber_register(f)
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

# The stacks of the live fibers, read until reading them reaches no
# more. An entry carries a bit that says its stack has been read in this
# collection: the low bit of the address, which a cell never has.
#
# The fiber running now is left out, as it was before: its task is the
# one `zr_mark_roots` walks, and its kernel roots are the live chain and
# not the copy the fiber holds.
sig [] => Void
machine def zr_mark_fibers
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
    more = false
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

# The entries of fibers the collection did not mark dropped, and the
# read bits taken off the rest. This runs beside `zr_weak_prune`, before
# the sweep frees a dead fiber's stack and its task.
sig [] => Void
machine def zr_fiber_prune
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

sig [Value] => Void
machine def zr_release_fiber(f)
  zr_xfree(RFiber.ctx(f))
  if RFiber.stack(f) != 0
    munmap(RFiber.stack(f), FIBER_STACK_BYTES)
    zr_xfree(RFiber.task(f))
  end
end

# The thread scheduler's switch: control moves to `to` with no rule
# checked and no flag set, so the fibers on either side keep the
# resume and transfer state they had.
sig [Value] => Value
machine def zr_fiber_scheduler_switch(to)
  cur = zr_fiber_current()
  if to == cur
    return Machine.value(QNIL)
  end
  zr_fiber_run(cur, to, 0, 0)
end
