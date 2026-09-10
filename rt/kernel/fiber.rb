# Fibers: each one a task of its own on a machine stack of its own,
# switched with the zr_switch stub. The current fiber's task is the
# task; the kernel root chain travels with the fiber.
Machine.raw "zr_switch"
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "munmap", [Ptr, Word] => I32

Machine.struct :RFiber, basic: RBasic, task: Ptr, ctx: Ptr, stack: Ptr, kroots: Ptr, blk: Value, status: Word, prev: Value, resuming: Value, value: Value, yielding: Word, transferred: Word
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
CONTEXT_BYTES = 176

sig [] => Ptr
machine def zr_current_task_slot
  Machine.static(:current_task, 8)
end

sig [] => Ptr
machine def zr_task
  Machine.ptr(Machine.load64(zr_current_task_slot(), 0))
end

sig [Ptr] => Void
machine def zr_task_init(t)
  Task.set_top(t, 0)
  Task.set_pending(t, Machine.value(QNIL))
  Task.set_pending_kind(t, PENDING_RAISE)
  Task.set_serial(t, 0)
  Task.set_errinfo(t, Machine.value(QNIL))
  Task.set_kw(t, 0)
  Task.set_guards(t, Machine.value(QNIL))
  Task.set_catches(t, Machine.value(QNIL))
  Task.set_throw_tag(t, Machine.value(QNIL))
  Task.set_mid(t, 0)
  Task.set_missing(t, 0)
  Task.set_found(t, Machine.value(QNIL))
  Task.set_refine(t, Machine.value(QNIL))
end

# The fiber running now; the root fiber stands for the main task.
sig [] => Value
machine def zr_fiber_current
  slot = Machine.static(:current_fiber, 8)
  f = Machine.value(Machine.load64(slot, 0))
  if zr_special_p(f)
    f = zr_alloc(T_FIBER, zr_global(G_FIBER))
    RFiber.set_task(f, Machine.static(:task, Task.size))
    RFiber.set_ctx(f, malloc(CONTEXT_BYTES))
    RFiber.set_stack(f, 0)
    RFiber.set_blk(f, Machine.value(QNIL))
    RFiber.set_status(f, FIBER_RESUMED)
    RFiber.set_prev(f, Machine.value(QNIL))
    RFiber.set_resuming(f, Machine.value(QNIL))
    RFiber.set_value(f, Machine.value(QNIL))
    RFiber.set_yielding(f, 0)
    RFiber.set_transferred(f, 0)
    Machine.store64(slot, 0, Machine.word(f))
    Machine.store64(Machine.static(:root_fiber, 8), 0, Machine.word(f))
  end
  f
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_current_m(recv, argc, argv, cref, blk)
  zr_fiber_current()
end

# `Fiber.new { }`: a task and a stack, and a context that starts at
# zr_fiber_start when first resumed.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_new(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
  end
  f = zr_alloc(T_FIBER, recv)
  RFiber.set_blk(f, blk)
  RFiber.set_status(f, FIBER_CREATED)
  RFiber.set_prev(f, Machine.value(QNIL))
  RFiber.set_resuming(f, Machine.value(QNIL))
  RFiber.set_value(f, Machine.value(QNIL))
  RFiber.set_yielding(f, 0)
  RFiber.set_transferred(f, 0)
  RFiber.set_kroots(f, 0)
  t = malloc(Task.size)
  zr_task_init(t)
  stack = mmap(0, FIBER_STACK_BYTES, 3, 4098, -1, 0)
  Task.set_stack_limit(t, stack + STACK_MARGIN)
  RFiber.set_task(f, t)
  RFiber.set_stack(f, stack)
  ctx = malloc(CONTEXT_BYTES)
  Machine.store64(ctx, 88, Machine.addr(:zr_fiber_start))
  Machine.store64(ctx, 96, stack + FIBER_STACK_BYTES)
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
  cur = zr_fiber_current()
  if RFiber.status(recv) == FIBER_TERMINATED
    return zr_fiber_error(Machine.bytes("attempt to resume a terminated fiber"), 36)
  end
  if recv == cur
    return zr_fiber_error(Machine.bytes("attempt to resume the current fiber"), 35)
  end
  if RFiber.resuming(recv) != QNIL
    return zr_fiber_error(Machine.bytes("attempt to resume a resuming fiber"), 34)
  end
  if RFiber.status(recv) == FIBER_RESUMED
    return zr_fiber_error(Machine.bytes("attempt to resume a resumed fiber (double resume)"), 49)
  end
  if RFiber.transferred(recv) != 0
    return zr_fiber_error(Machine.bytes("attempt to resume a transferring fiber"), 38)
  end
  RFiber.set_prev(recv, cur)
  RFiber.set_resuming(cur, recv)
  RFiber.set_yielding(recv, 0)
  zr_fiber_run(cur, recv, argc, argv)
end

# `transfer(*args)`: control moves to the fiber with no way back but
# another transfer; when it ends, control returns to the root fiber's
# deepest resumed fiber.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_fiber_transfer(recv, argc, argv, cref, blk)
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
  RFiber.set_transferred(cur, 1)
  RFiber.set_status(cur, FIBER_SUSPENDED)
  zr_fiber_run(cur, recv, argc, argv)
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
  f = zr_fiber_root()
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
  v
end

# A fresh fiber's first instruction: the block with the first resume's
# arguments; when it ends, its value or its pending signal goes to the
# fiber control returns to, and the stack is never returned to.
sig [] => Void
machine def zr_fiber_start
  cur = zr_fiber_current()
  args = RFiber.value(cur)
  r = zr_yield(RFiber.blk(cur), RArray.len(args), RArray.ptr(args))
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
  zr_bool(RFiber.status(recv) != FIBER_TERMINATED)
end

# A suspended fiber's roots: its frame chain, its task's slots, and the
# kernel records on its stack.
sig [Value] => Void
machine def zr_mark_fiber(f)
  zr_mark(RFiber.blk(f))
  zr_mark(RFiber.prev(f))
  zr_mark(RFiber.resuming(f))
  zr_mark(RFiber.value(f))
  if Machine.word(f) != Machine.load64(Machine.static(:current_fiber, 8), 0)
    zr_mark_task(RFiber.task(f))
    zr_mark_kernel_roots_from(RFiber.kroots(f))
  end
end

sig [Value] => Void
machine def zr_release_fiber(f)
  free(RFiber.ctx(f))
  if RFiber.stack(f) != 0
    munmap(RFiber.stack(f), FIBER_STACK_BYTES)
    free(RFiber.task(f))
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
