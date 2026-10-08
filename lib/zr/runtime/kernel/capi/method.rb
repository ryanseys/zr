module Zr::Kern
  # Methods whose bodies are C functions, and the C API's calls of Ruby.

  # The builtin of every method that C defines (`zr_capi_define`): it
  # calls the C function that the method's FrameMeta keeps, with the
  # arguments in the form that its arity gives, as CRuby's call of a C
  # method does:
  # - 0 to 15: `fn(self, a1, ..., an)`; the dispatch checked the count;
  # - -1: `fn(argc, argv, self)`;
  # - -2: `fn(self, args)`, with the arguments in an Array.
  # Keywords go to C as a last Hash. The caller's dispatch made this
  # call's frame, so `Task.top` is it: rb_yield and rb_block_given_p read
  # its block.
  #: (value, word, ptr, value, value) -> value
  def zr_cfunc_call(recv, argc, argv, cref, blk)
    t = zr_task()
    kw = Task[t].kw
    if kw != 0
      Task[t].kw = 0
      argc = zr_kw_undeclared(kw, argc, argv, 0)
    end
    meta = Frame[Task[t].top].meta
    arity = FrameMeta[meta].arity
    # Self and up to fifteen arguments, at least the eight words that
    # zr_call_c reads.
    args = Machine.slot(128)
    n = 0
    if arity == 0 - 1
      Machine.store64(args, 0, argc)
      Machine.store64(args, 8, Machine.word(argv))
      Machine.store64(args, 16, Machine.word(recv))
      n = 3
    elsif arity == 0 - 2
      list = zr_ary_new(argc)
      i = 0
      while i < argc
        zr_ary_push(list, Machine.value(Machine.load64(argv + (i * 8), 0)))
        i += 1
      end
      Machine.store64(args, 0, Machine.word(recv))
      Machine.store64(args, 8, Machine.word(list))
      n = 2
    else
      Machine.store64(args, 0, Machine.word(recv))
      i = 0
      while i < arity
        Machine.store64(args + ((i + 1) * 8), 0, Machine.load64(argv + (i * 8), 0))
        i += 1
      end
      n = arity + 1
    end
    Machine.value(zr_call_c(FrameMeta[meta].fn, args, n))
  end

  # rb_need_block's LocalJumpError, which CRuby's yield from C raises with
  # no block: `no block given`, without the `(yield)` of a Ruby yield.
  #: () -> void
  def zr_capi_need_block
    if zr_capi_block() == QNIL
      zr_c_result(zr_local_jump_error(Machine.bytes("no block given"), 14, Machine.id(:noreason), Machine.value(QNIL)))
    end
  end

  # The block of the C method that runs: its frame's.
  #: () -> value
  def zr_capi_block
    Frame[Task[zr_task()].top].blk
  end

  # rb_funcallv: calls the method `mid` of `recv`, private ones too, with
  # the `argc` arguments at `argv`.
  #: (value, word, i32, ptr) -> value
  def rb_funcallv(recv, mid, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(recv, zr_capi_mid(mid), Machine.sword(argc), argv))
  end

  # rb_funcallv_public: the same, for a public method only, as a call
  # with an explicit receiver.
  #: (value, word, i32, ptr) -> value
  def rb_funcallv_public(recv, mid, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_dispatch(0, recv, zr_capi_mid(mid), Machine.sword(argc), argv, 2, Machine.value(QNIL)))
  end

  # rb_block_given_p: whether the C method got a block.
  #: () -> i32
  def rb_block_given_p
    Machine.gates_enter
    zr_c_entered()
    zr_capi_block() == QNIL ? Machine.i32(0) : Machine.i32(1)
  end

  # rb_yield: calls the C method's block with one argument, or with none
  # when `v` is undef (CRuby's rb_yield(Qundef)).
  #: (value) -> value
  def rb_yield(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_need_block()
    if v == QUNDEF
      return zr_c_result(zr_yield(zr_capi_block(), 0, Machine.slot(8)))
    end
    zr_c_result(zr_yield1(zr_capi_block(), v))
  end

  # rb_yield_values2: calls the block with the `argc` values at `argv`.
  #: (i32, ptr) -> value
  def rb_yield_values2(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_need_block()
    zr_c_result(zr_yield(zr_capi_block(), Machine.sword(argc), argv))
  end
end
