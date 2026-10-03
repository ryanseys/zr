# Continuations. `callcc` saves the machine stack from its current
# position to the top of the fiber's stack, with the machine context and
# the task. A call runs on a separate side stack. It puts all of them
# back at the same addresses and resumes where the capture switched
# away. No object moves in the heap, so the references in the copy stay
# correct. An Array in the Continuation keeps the Values of the saved
# frames alive.

module Zr::Kern
  # `low` and `high` are the limits of the saved stack, and `bytes`
  # contains its bytes. `ctx` is the context that the capture switched
  # away from. `task` is a copy of the task at that time, and `kroots` is
  # the kernel's root list at that time. `resumed` is 1 after a call
  # comes back through the capture.
  class ContState < Layout
    attr_accessor :low #: word
    attr_accessor :high #: word
    attr_accessor :bytes #: ptr
    attr_accessor :ctx #: ptr
    attr_accessor :task #: ptr
    attr_accessor :kroots #: ptr
    attr_accessor :resumed #: word
  end
  CONT_SIDE_BYTES = 1048576
  CONT_CAPTURE = 1
  CONT_RESTORE = 2

  #: () -> ptr
  def zr_cont_side_ctx
    Machine.static(:cont_side_ctx, CONTEXT_BYTES)
  end

  # The work on the side stack. `cont_op` identifies the state, and
  # `cont_mode` identifies the job: copy the stack out, or copy it back.
  # Then it switches back to the capture's context.
  #: () -> void
  def zr_cont_side
    while true
      s = Machine.ptr(Machine.load64(Machine.static(:cont_op, 8), 0))
      if Machine.load64(Machine.static(:cont_mode, 8), 0) == CONT_CAPTURE
        low = zr_arch_context_sp(ContState[s].ctx)
        size = ContState[s].high - low
        bytes = zr_xmalloc(size)
        zr_memcpy(bytes, Machine.ptr(low), size)
        ContState[s].low = low
        ContState[s].bytes = bytes
      else
        zr_memcpy(Machine.ptr(ContState[s].low), ContState[s].bytes, ContState[s].high - ContState[s].low)
      end
      zr_switch(zr_cont_side_ctx(), ContState[s].ctx)
    end
  end

  # The top of the current fiber's stack, or 0 if the host does not give
  # access to it.
  #: () -> word
  def zr_cont_stack_high
    f = zr_fiber_current()
    if RFiber[f].stack != 0
      return Machine.word(RFiber[f].stack) + FIBER_STACK_BYTES
    end
    zr_os_stack_high()
  end

  # Adds `v` to `roots`, where the collector reads it while the
  # continuation is alive. A Proc or an Env on the machine stack is not in
  # an arena, and the saved stack restores its bytes. But its frame can
  # return before the continuation is called. Then that stack memory
  # contains other bytes, and a pointer in `roots` would make the
  # collector read them as a cell. Thus zr adds only the objects that such
  # a cell refers to. The frame loop adds the Values in an Env's slots,
  # because they belong to the frame record.
  #: (value, value) -> void
  def zr_cont_root(roots, v)
    if zr_special_p(v) || (RBasic[v].flags & FL_STACK) == 0
      zr_ary_push(roots, v)
    elsif (RBasic[v].flags & T_MASK) == T_PROC
      zr_cont_root(roots, RProc[v].env)
      zr_cont_root(roots, RProc[v].self)
      zr_cont_root(roots, RProc[v].cref)
      zr_cont_root(roots, RProc[v].blk)
    else
      zr_cont_root(roots, REnv[v].parent)
      zr_cont_root(roots, REnv[v].cell)
    end
  end

  # Adds each Value in the frames and in the kernel's roots to `roots`.
  #: (value) -> void
  def zr_cont_roots(roots)
    t = zr_task()
    rec = Task[t].top
    while rec != 0
      zr_cont_root(roots, Frame[rec].self)
      zr_cont_root(roots, Frame[rec].cref)
      zr_ary_push(roots, zr_block_proc(Frame[rec].blk))
      zr_cont_root(roots, Frame[rec].svars)
      # A block's frame keeps there the block that its call received.
      zr_ary_push(roots, zr_block_proc(Frame[rec].defined))
      # A frame record's Env image is on the stack, not in a cell. Its
      # slots belong to the frame record, so this loop adds them here.
      i = 0
      while i < Frame[rec].nvalues
        zr_cont_root(roots, Machine.value(Machine.load64(rec + Frame.size + (i * 8), 0)))
        i += 1
      end
      rec = Frame[rec].prev
    end
    frame = Machine.ptr(Machine.load64(zr_kroots(), 0))
    while frame != 0
      i = 0
      while i < Machine.load64(frame, 8)
        zr_cont_root(roots, Machine.value(Machine.load64(frame + 16 + (i * 8), 0)))
        i += 1
      end
      frame = Machine.ptr(Machine.load64(frame, 0))
    end
    zr_cont_root(roots, Task[t].pending)
    zr_cont_root(roots, Task[t].errinfo)
    zr_cont_root(roots, Task[t].guards)
    zr_cont_root(roots, Task[t].catches)
    zr_cont_root(roots, Task[t].throw_tag)
    zr_cont_root(roots, Task[t].found)
    zr_cont_root(roots, Task[t].refine)
  end

  # Captures the `callcc` state into `cont`. Returns false the first time,
  # and true each time a call comes back through the capture.
  #: (value) -> value
  def zr_cont_capture(cont)
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
    ContState[s].high = high
    ContState[s].ctx = zr_xmalloc(CONTEXT_BYTES)
    ContState[s].task = zr_xmalloc(Task.size)
    zr_memcpy(ContState[s].task, zr_task(), Task.size)
    ContState[s].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    ContState[s].resumed = 0
    zr_hidden_set(cont, zr_sym(Machine.id(:__state__)), zr_fix(Machine.word(s)))
    zr_hidden_set(cont, zr_sym(Machine.id(:__fiber__)), zr_fiber_current())
    Machine.store64(Machine.static(:cont_op, 8), 0, Machine.word(s))
    Machine.store64(Machine.static(:cont_mode, 8), 0, CONT_CAPTURE)
    zr_switch(ContState[s].ctx, zr_cont_side_ctx())
    zr_bool(ContState[s].resumed != 0)
  end

  # Calls `cont`. It restores the task, the kernel's roots and the stack
  # as the capture saved them. Then it resumes the capture's context, so
  # this function does not return.
  #: (value) -> value
  def zr_cont_resume(cont)
    s = Machine.ptr(zr_fix2long(zr_hidden_get(cont, zr_sym(Machine.id(:__state__)))))
    ContState[s].resumed = 1
    zr_memcpy(zr_task(), ContState[s].task, Task.size)
    Machine.store64(zr_kroots(), 0, Machine.word(ContState[s].kroots))
    Machine.store64(Machine.static(:cont_op, 8), 0, Machine.word(s))
    Machine.store64(Machine.static(:cont_mode, 8), 0, CONT_RESTORE)
    zr_switch(Machine.slot(CONTEXT_BYTES), zr_cont_side_ctx())
    Machine.value(QNIL)
  end
end
