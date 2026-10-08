module Zr::Kern
  # C functions as blocks, and the C API's calls of Procs.
  #
  # rb_block_call and rb_proc_new make a C block: a Proc whose `fn` is
  # zr_capi_cblock, which calls a C block function as CRuby calls an
  # IFUNC, `fn(yielded, data2, argc, argv, blockarg)`. The Proc's self is
  # an Array that keeps the function and its data word as Integers, and
  # the data word itself when it is a cell, so the collector keeps what C
  # handed over. Its `blk` is the block of the C method that made it:
  # rb_yield in the block function yields to that block, as the yield of
  # an IFUNC does. rb_thread_create and rb_fiber_new make the same kind
  # of Proc over another adapter.

  # rb_block_call: `obj.mid(*argv)` with a block that calls `bl_proc`
  # for each yield, or with the C method's own block when `bl_proc` is
  # NULL. rb_iter_break in the block function ends the call.
  #: (value, word, i32, ptr, ptr, word) -> value
  def rb_block_call(obj, mid, argc, argv, bl_proc, data2)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_block_call(obj, zr_capi_mid(mid), Machine.sword(argc), argv, bl_proc, data2, Machine.i32(0))
  end

  # rb_block_call_kw: the same, the last argument the keywords when
  # `kw_splat` is not 0.
  #: (value, word, i32, ptr, ptr, word, i32) -> value
  def rb_block_call_kw(obj, mid, argc, argv, bl_proc, data2, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_block_call(obj, zr_capi_mid(mid), Machine.sword(argc), argv, bl_proc, data2, kw_splat)
  end

  # The call runs under a catch whose tag is the C block, which
  # rb_iter_break throws to.
  #: (value, word, word, ptr, ptr, word, i32) -> value
  def zr_capi_block_call(obj, mid, argc, argv, fn, data2, kw_splat)
    if fn == 0
      return zr_c_result(zr_capi_send_blk(obj, mid, argc, argv, kw_splat, zr_capi_block()))
    end
    blk = zr_capi_cblock_new(fn, data2)
    catches = zr_catches()
    zr_ary_push(catches, blk)
    r = zr_capi_send_blk(obj, mid, argc, argv, kw_splat, blk)
    RArray[catches].len = RArray[catches].len - 1
    zr_c_result(zr_caught(r, blk))
  end

  # rb_each: `obj.each`, with no block: rb_iterate gave it one.
  #: (value) -> value
  def rb_each(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:each), 0, Machine.ptr(0)))
  end

  # rb_proc_new: a Proc that calls `fn(yielded, val, argc, argv,
  # blockarg)`.
  #: (ptr, value) -> value
  def rb_proc_new(fn, val)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_cblock_new(fn, Machine.word(val))
  end

  # rb_iter_break: ends the rb_block_call whose block function runs,
  # which returns nil.
  #: () -> void
  def rb_iter_break
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iter_break(Machine.value(QNIL))
  end

  # rb_iter_break_value: the same, and that call returns `v`.
  #: (value) -> void
  def rb_iter_break_value(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iter_break(v)
  end

  # Throws `v` to the innermost C block's catch. With none, the break has
  # nothing to leave: `unexpected break`. (CRuby breaks out of the Ruby
  # block that called the C method then.)
  #: (value) -> void
  def zr_capi_iter_break(v)
    catches = zr_catches()
    i = RArray[catches].len - 1
    while i >= 0
      tag = zr_ary_at(catches, i)
      if zr_capi_cblock_p(tag)
        zr_throw(tag, v)
        zr_c_unwind()
      end
      i -= 1
    end
    zr_c_result(zr_local_jump_error(Machine.bytes("unexpected break"), 16, Machine.id(:break), v))
  end

  # rb_yield_splat: calls the C method's block with the elements of the
  # Array `values` as its arguments.
  #: (value) -> value
  def rb_yield_splat(values)
    Machine.gates_enter
    zr_c_entered()
    ary = zr_capi_check_convert(values, T_ARRAY, Machine.bytes("Array"), 5, Machine.id(:to_ary))
    if ary == QNIL
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("not an array"), 12)
    end
    zr_capi_need_block()
    zr_c_result(zr_yield(zr_capi_block(), RArray[ary].len, RArray[ary].ptr))
  end

  # rb_proc_call: `proc.call(*args)`.
  #: (value, value) -> value
  def rb_proc_call(proc, args)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(proc, Machine.id(:call), RArray[args].len, RArray[args].ptr))
  end

  # rb_proc_arity: Proc#arity.
  #: (value) -> i32
  def rb_proc_arity(proc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_fix2long(zr_c_result(zr_send(proc, Machine.id(:arity), 0, Machine.ptr(0)))))
  end

  # rb_proc_lambda_p: Proc#lambda?.
  #: (value) -> value
  def rb_proc_lambda_p(proc)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(proc, Machine.id(:lambda?), 0, Machine.ptr(0)))
  end

  # rb_method_call: `method.call(*argv)`.
  #: (i32, ptr, value) -> value
  def rb_method_call(argc, argv, method)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(method, Machine.id(:call), Machine.sword(argc), argv))
  end

  # rb_exec_recursive: calls `fn(obj, arg, recursive)`, where `recursive`
  # is 1 when the C method that runs is already running on `obj` in this
  # thread, as `inspect` of an Array that contains itself finds.
  #: (ptr, value, value) -> value
  def rb_exec_recursive(fn, obj, arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_exec_recursive(fn, obj, Machine.value(QUNDEF), arg)
  end

  # rb_exec_recursive_paired: the same, for the pair `obj` and `paired`,
  # as `==` on two structures that contain themselves finds.
  #: (ptr, value, value, value) -> value
  def rb_exec_recursive_paired(fn, obj, paired, arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_exec_recursive(fn, obj, paired, arg)
  end

  # The guard is the C method's name on `obj` (and `paired`), so each C
  # method finds only its own recursion.
  #: (ptr, value, value, value) -> value
  def zr_capi_exec_recursive(fn, obj, paired, arg)
    mid = FrameMeta[Frame[Task[zr_task()].top].meta].name
    args = Machine.slot(64)
    Machine.store64(args, 0, Machine.word(obj))
    Machine.store64(args, 8, Machine.word(arg))
    if zr_guard_enter_paired(obj, paired, mid)
      Machine.store64(args, 16, 1)
      return zr_c_result(Machine.value(zr_call_c(fn, args, 3)))
    end
    Machine.store64(args, 16, 0)
    r = Machine.value(zr_call_c(fn, args, 3))
    zr_guard_leave(obj, mid)
    zr_c_result(r)
  end

  # A C block over `fn` and its data word. It is not a lambda: the
  # yield's values reach C as they were given.
  #: (ptr, word) -> value
  def zr_capi_cblock_new(fn, data)
    zr_capi_native_proc(Machine.addr(:zr_capi_cblock), fn, data)
  end

  # A Proc whose `fn` is `adapter`, which calls the C function `fn` with
  # its data word, both kept in its self (zr_capi_proc_fn and
  # zr_capi_proc_data read them).
  #: (ptr, ptr, word) -> value
  def zr_capi_native_proc(adapter, fn, data)
    # A data word that is a cell can be in no other root (a String that C
    # made for the call), so it is a Value of this frame before anything
    # allocates.
    held = Machine.value(QNIL)
    if zr_live_cell_p(data)
      held = Machine.value(data)
    end
    kept = zr_ary_new(3)
    RBasic[kept].flags = RBasic[kept].flags | FL_CONCEALED
    zr_ary_push(kept, zr_int_from_word(Machine.word(fn)))
    zr_ary_push(kept, zr_c_result(zr_int_from_word(data)))
    zr_ary_push(kept, held)
    p = zr_native_proc(adapter, kept)
    RProc[p].lambda = 0
    blk = zr_capi_block()
    RProc[p].blk = blk == QNIL ? blk : zr_block_proc(blk)
    p
  end

  #: (value) -> ptr
  def zr_capi_proc_fn(p)
    Machine.ptr(zr_fix2long(zr_ary_at(RProc[p].self, 0)))
  end

  #: (value) -> word
  def zr_capi_proc_data(p)
    zr_capi_ulong_of(zr_ary_at(RProc[p].self, 1), true)
  end

  #: (value) -> bool
  def zr_capi_cblock_p(v)
    !zr_special_p(v) && zr_type(v) == T_PROC && RProc[v].fn == Machine.addr(:zr_capi_cblock)
  end

  # The `fn` of a C block: calls the C function with the first value
  # yielded (nil for none), the data word, all the values, and the block
  # that the yield passed (nil for none). It runs under a frame of its
  # own whose block is the C method's, which no backtrace shows.
  #: (value, word, ptr, value) -> value
  def zr_capi_cblock(p, argc, argv, blk)
    args = Machine.slot(64)
    Machine.store64(args, 0, argc > 0 ? Machine.load64(argv, 0) : QNIL)
    Machine.store64(args, 8, zr_capi_proc_data(p))
    Machine.store64(args, 16, argc)
    Machine.store64(args, 24, Machine.word(argv))
    Machine.store64(args, 32, Machine.word(blk == QNIL ? blk : zr_block_proc(blk)))
    rec = Machine.slot(Frame.size)
    t = zr_task()
    if Machine.word(rec) < Machine.word(Task[t].stack_limit)
      return zr_stack_overflow()
    end
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = zr_capi_cblock_meta()
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].self = Machine.value(QNIL)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = RProc[p].blk
    Frame[rec].nvalues = 0
    Frame[rec].entry = 0
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    r = Machine.value(zr_call_c(zr_capi_proc_fn(p), args, 5))
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  # The frame data of a C block's frame: hidden, with no name or file.
  #: () -> ptr
  def zr_capi_cblock_meta
    meta = Machine.static(:capi_cblock_meta, FrameMeta.size)
    if FrameMeta[meta].kind != KIND_HIDDEN
      FrameMeta[meta].kind = KIND_HIDDEN
      FrameMeta[meta].owner = Machine.value(QNIL)
    end
    meta
  end
end
