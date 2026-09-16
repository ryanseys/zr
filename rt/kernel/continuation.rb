# Continuations: `callcc` saves the machine stack from where it stands to
# the top of the fiber's stack, with the machine context and the task,
# and a call puts them all back at the same addresses, from a side stack
# of its own, and resumes where the capture switched away. Nothing moves
# in the heap, so the copy's references stand; the Values the saved
# frames hold stay alive in an Array the Continuation keeps.

# `low` and `high` bound the saved stack, whose bytes `bytes` holds;
# `ctx` is the context the capture switched away from, `task` a copy of
# the task then, and `kroots` the kernel's root chain then. `resumed` is 1
# once a call comes back through the capture.
Machine.struct :ContState, low: Word, high: Word, bytes: Ptr, ctx: Ptr, task: Ptr, kroots: Ptr, resumed: Word
CONT_SIDE_BYTES = 1048576
CONT_CAPTURE = 1
CONT_RESTORE = 2

sig [] => Ptr
machine def zr_cont_side_ctx
  Machine.static(:cont_side_ctx, CONTEXT_BYTES)
end

# The side stack's work: `cont_op` names the state and `cont_mode` the
# job, copying the stack out of place or back into it, and then the
# switch back to the capture's context.
sig [] => Void
machine def zr_cont_side
  while true
    s = Machine.ptr(Machine.load64(Machine.static(:cont_op, 8), 0))
    if Machine.load64(Machine.static(:cont_mode, 8), 0) == CONT_CAPTURE
      low = Machine.load64(ContState.ctx(s), 96)
      size = ContState.high(s) - low
      bytes = zr_xmalloc(size)
      zr_memcpy(bytes, Machine.ptr(low), size)
      ContState.set_low(s, low)
      ContState.set_bytes(s, bytes)
    else
      zr_memcpy(Machine.ptr(ContState.low(s)), ContState.bytes(s), ContState.high(s) - ContState.low(s))
    end
    zr_switch(zr_cont_side_ctx(), ContState.ctx(s))
  end
end

# The top of the current fiber's stack, or 0 where the host keeps it out
# of reach.
sig [] => Word
machine def zr_cont_stack_high
  f = zr_fiber_current()
  if RFiber.stack(f) != 0
    return Machine.word(RFiber.stack(f)) + FIBER_STACK_BYTES
  end
  zr_os_stack_high()
end

# Every Value the frames and the kernel's roots hold now, into `roots`.
sig [Value] => Void
machine def zr_cont_roots(roots)
  t = zr_task()
  rec = Task.top(t)
  while rec != 0
    zr_ary_push(roots, Frame.self(rec))
    zr_ary_push(roots, Frame.cref(rec))
    zr_ary_push(roots, zr_block_proc(Frame.blk(rec)))
    zr_ary_push(roots, Frame.svars(rec))
    # a block's frame keeps the block its call was given there
    zr_ary_push(roots, zr_block_proc(Frame.defined(rec)))
    # A record's Env image is the stack's, not a cell: its slots are
    # the record's own, pushed here as they come.
    i = 0
    while i < Frame.nvalues(rec)
      v = Machine.value(Machine.load64(rec + Frame.size + (i * 8), 0))
      if !zr_special_p(v) && (RBasic.flags(v) & FL_STACK) != 0
        v = Machine.value(QNIL)
      end
      zr_ary_push(roots, v)
      i += 1
    end
    rec = Frame.prev(rec)
  end
  frame = Machine.ptr(Machine.load64(zr_kroots(), 0))
  while frame != 0
    i = 0
    while i < Machine.load64(frame, 8)
      zr_ary_push(roots, Machine.value(Machine.load64(frame + 16 + (i * 8), 0)))
      i += 1
    end
    frame = Machine.ptr(Machine.load64(frame, 0))
  end
  zr_ary_push(roots, Task.pending(t))
  zr_ary_push(roots, Task.errinfo(t))
  zr_ary_push(roots, Task.guards(t))
  zr_ary_push(roots, Task.catches(t))
  zr_ary_push(roots, Task.throw_tag(t))
  zr_ary_push(roots, Task.found(t))
  zr_ary_push(roots, Task.refine(t))
end

# `callcc`'s capture into `cont`: false as it returns the first time,
# true each time a call comes back through it.
sig [Value] => Value
machine def zr_cont_capture(cont)
  high = zr_cont_stack_high()
  if high == 0
    return zr_unimplemented(zr_str_new(Machine.bytes("callcc where the stack is out of reach"), 38))
  end
  side = Machine.static(:cont_side_ready, 8)
  if Machine.load64(side, 0) == 0
    stack = zr_os_stack_map(CONT_SIDE_BYTES)
    if stack == 0
      return zr_fiber_stack_error(zr_errno())
    end
    zr_arch_context_start(zr_cont_side_ctx(), Machine.addr(:zr_cont_side), Machine.word(stack) + CONT_SIDE_BYTES)
    Machine.store64(side, 0, 1)
  end
  roots = zr_ary_new(64)
  zr_hidden_set(cont, zr_sym(Machine.id(:__roots__)), roots)
  zr_cont_roots(roots)
  s = zr_xmalloc(ContState.size)
  ContState.set_high(s, high)
  ContState.set_ctx(s, zr_xmalloc(CONTEXT_BYTES))
  ContState.set_task(s, zr_xmalloc(Task.size))
  zr_memcpy(ContState.task(s), zr_task(), Task.size)
  ContState.set_kroots(s, Machine.ptr(Machine.load64(zr_kroots(), 0)))
  ContState.set_resumed(s, 0)
  zr_hidden_set(cont, zr_sym(Machine.id(:__state__)), zr_fix(Machine.word(s)))
  zr_hidden_set(cont, zr_sym(Machine.id(:__fiber__)), zr_fiber_current())
  Machine.store64(Machine.static(:cont_op, 8), 0, Machine.word(s))
  Machine.store64(Machine.static(:cont_mode, 8), 0, CONT_CAPTURE)
  zr_switch(ContState.ctx(s), zr_cont_side_ctx())
  zr_bool(ContState.resumed(s) != 0)
end

# A call of `cont`: the task, the kernel's roots and the stack as the
# capture left them, and the capture's context resumed, which never
# comes back here.
sig [Value] => Value
machine def zr_cont_resume(cont)
  s = Machine.ptr(zr_fix2long(zr_hidden_get(cont, zr_sym(Machine.id(:__state__)))))
  ContState.set_resumed(s, 1)
  zr_memcpy(zr_task(), ContState.task(s), Task.size)
  Machine.store64(zr_kroots(), 0, Machine.word(ContState.kroots(s)))
  Machine.store64(Machine.static(:cont_op, 8), 0, Machine.word(s))
  Machine.store64(Machine.static(:cont_mode, 8), 0, CONT_RESTORE)
  zr_switch(Machine.slot(CONTEXT_BYTES), zr_cont_side_ctx())
  Machine.value(QNIL)
end
