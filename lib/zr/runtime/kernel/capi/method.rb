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
    keywords = Task[t].c_keywords
    Task[t].c_keywords = 0
    if kw != 0
      Task[t].kw = 0
      argc = zr_kw_undeclared(kw, argc, argv, 0)
      Task[t].c_keywords = 1
    end
    rec = Task[t].top
    meta = Frame[rec].meta
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
    r = Machine.value(zr_call_c(FrameMeta[meta].fn, args, n))
    Task[zr_task()].c_keywords = keywords
    zr_capi_trace_returned(rec, recv, r)
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

  # rb_funcall: calls `mid` of `recv` with the `n` Values that follow.
  #: (value, word, i32) -> value
  def rb_funcall(recv, mid, n)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.va_list(VA_LIST_KIND)
    count = Machine.sword(n)
    room = Machine.slot(CAPI_ARGS * 8)
    args = zr_capi_va_values(list, count, room)
    zr_c_result(zr_send(recv, zr_capi_mid(mid), count, zr_capi_args_at(args, room)))
  end

  # rb_yield_values: calls the block with the `n` Values that follow.
  #: (i32) -> value
  def rb_yield_values(n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_need_block()
    list = Machine.va_list(VA_LIST_KIND)
    count = Machine.sword(n)
    room = Machine.slot(CAPI_ARGS * 8)
    args = zr_capi_va_values(list, count, room)
    zr_c_result(zr_yield(zr_capi_block(), count, zr_capi_args_at(args, room)))
  end

  # The variadic Values of a call fit in a slot of this many words; more
  # go to an Array.
  CAPI_ARGS = 16

  # Reads `n` Values from `list` into `room` when they fit, and returns
  # nil; else into a new Array, which it returns.
  #: (ptr, word, ptr) -> value
  def zr_capi_va_values(list, n, room)
    if n <= CAPI_ARGS
      i = 0
      while i < n
        Machine.store64(room + (i * 8), 0, zr_va_next_word(list))
        i += 1
      end
      return Machine.value(QNIL)
    end
    ary = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(ary, Machine.value(zr_va_next_word(list)))
      i += 1
    end
    ary
  end

  # Where zr_capi_va_values put the Values.
  #: (value, ptr) -> ptr
  def zr_capi_args_at(ary, room)
    ary == QNIL ? room : RArray[ary].ptr
  end

  # rb_keyword_given_p: whether the C method that runs got keywords.
  #: () -> i32
  def rb_keyword_given_p
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(Task[zr_task()].c_keywords)
  end

  # rb_block_proc: the C method's block as a Proc.
  #: () -> value
  def rb_block_proc
    Machine.gates_enter
    zr_c_entered()
    zr_capi_need_block()
    zr_block_proc(zr_capi_block())
  end

  # rb_need_block: raises LocalJumpError unless the C method got a block.
  #: () -> void
  def rb_need_block
    Machine.gates_enter
    zr_c_entered()
    zr_capi_need_block()
  end

  # rb_error_arity: `wrong number of arguments (given argc, expected
  # min..max)`, with max -1 for no limit.
  #: (i32, i32, i32) -> void
  def rb_error_arity(argc, min, max)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_wrong_arity_kw(Machine.sword(argc), Machine.sword(min), Machine.sword(max), Machine.ptr(0), 0))
  end

  # rb_scan_args's keyword flags (RB_SCAN_ARGS_*).
  SCAN_ARGS_PASS_CALLED_KEYWORDS = 0
  SCAN_ARGS_KEYWORDS = 1
  SCAN_ARGS_LAST_HASH_KEYWORDS = 3

  # rb_scan_args: sorts `argc` arguments at `argv` into the VALUE
  # variables whose addresses follow `fmt`, as the format asks: leading,
  # optional, rest, trailing, keywords, block. Returns `argc`.
  #: (i32, ptr, ptr) -> i32
  def rb_scan_args(argc, argv, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.va_list(VA_LIST_KIND)
    Machine.i32(zr_capi_scan_args(SCAN_ARGS_PASS_CALLED_KEYWORDS, Machine.sword(argc), argv, fmt, list))
  end

  # rb_scan_args_kw: the same, with the keywords as `kw_flag` says.
  #: (i32, i32, ptr, ptr) -> i32
  def rb_scan_args_kw(kw_flag, argc, argv, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.va_list(VA_LIST_KIND)
    Machine.i32(zr_capi_scan_args(Machine.sword(kw_flag), Machine.sword(argc), argv, fmt, list))
  end

  # rb_scan_args_parse and rb_scan_args_assign. The format is up to two
  # digits (leading and optional), `*`, a digit (trailing), `:` and `&`.
  #: (word, word, ptr, ptr, ptr) -> word
  def zr_capi_scan_args(kw_flag, argc, argv, fmt, list)
    at = 0
    lead = 0
    opt = 0
    trail = 0
    if zr_capi_digit_p(fmt, at)
      lead = zr_capi_fmt_byte(fmt, at) - 48
      at += 1
      if zr_capi_digit_p(fmt, at)
        opt = zr_capi_fmt_byte(fmt, at) - 48
        at += 1
      end
    end
    rest = zr_capi_fmt_byte(fmt, at) == 42
    if rest
      at += 1
    end
    if zr_capi_digit_p(fmt, at)
      trail = zr_capi_fmt_byte(fmt, at) - 48
      at += 1
    end
    keywords = zr_capi_fmt_byte(fmt, at) == 58
    if keywords
      at += 1
    end
    block = zr_capi_fmt_byte(fmt, at) == 38
    if block
      at += 1
    end
    if zr_capi_fmt_byte(fmt, at) != 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("bad scan arg format: "), 21)
      zr_buf_push(b, fmt, zr_cstr_len(fmt))
      zr_c_result(zr_raise_buf(zr_global(G_FATAL), b))
    end
    # The option hash comes off the end first.
    hash = Machine.value(QNIL)
    if keywords && argc > 0
      last = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
      if zr_capi_keywords_p(kw_flag, last)
        hash = zr_c_result(zr_hash_dup_m(last))
        argc -= 1
      end
    end
    mandatory = lead + trail
    if argc < mandatory
      zr_capi_scan_arity(argc, mandatory, opt, rest)
    end
    argi = 0
    i = 0
    while i < lead
      zr_capi_scan_set(list, Machine.value(Machine.load64(argv + (argi * 8), 0)))
      argi += 1
      i += 1
    end
    i = 0
    while i < opt
      if argi < argc - trail
        zr_capi_scan_set(list, Machine.value(Machine.load64(argv + (argi * 8), 0)))
        argi += 1
      else
        zr_capi_scan_set(list, Machine.value(QNIL))
      end
      i += 1
    end
    if rest
      n = argc - argi - trail
      ary = zr_ary_new(n > 0 ? n : 0)
      while argi < argc - trail
        zr_ary_push(ary, Machine.value(Machine.load64(argv + (argi * 8), 0)))
        argi += 1
      end
      zr_capi_scan_set(list, ary)
    end
    i = 0
    while i < trail
      zr_capi_scan_set(list, Machine.value(Machine.load64(argv + (argi * 8), 0)))
      argi += 1
      i += 1
    end
    if keywords
      zr_capi_scan_set(list, hash)
    end
    if block
      zr_capi_scan_set(list, zr_block_proc(zr_capi_block()))
    end
    if argi != argc
      zr_capi_scan_arity(argc, mandatory, opt, rest)
    end
    argc
  end

  # Whether the last argument is the keywords, as `kw_flag` decides.
  #: (word, value) -> bool
  def zr_capi_keywords_p(kw_flag, last)
    if kw_flag == SCAN_ARGS_PASS_CALLED_KEYWORDS
      return Task[zr_task()].c_keywords != 0
    end
    if kw_flag == SCAN_ARGS_KEYWORDS
      return true
    end
    kw_flag == SCAN_ARGS_LAST_HASH_KEYWORDS && zr_type(last) == T_HASH
  end

  # Stores `v` in the VALUE variable whose address is next, unless it is
  # NULL.
  #: (ptr, value) -> void
  def zr_capi_scan_set(list, v)
    at = Machine.ptr(zr_va_next_word(list))
    if at != 0
      Machine.store64(at, 0, Machine.word(v))
    end
  end

  # rb_scan_args_result's ArgumentError.
  #: (word, word, word, bool) -> void
  def zr_capi_scan_arity(argc, mandatory, opt, rest)
    zr_c_result(zr_wrong_arity_kw(argc, mandatory, rest ? 0 - 1 : mandatory + opt, Machine.ptr(0), 0))
  end

  #: (ptr, word) -> word
  def zr_capi_fmt_byte(fmt, at)
    Machine.word(Machine.u8(Machine.load8(fmt + at, 0)))
  end

  #: (ptr, word) -> bool
  def zr_capi_digit_p(fmt, at)
    c = zr_capi_fmt_byte(fmt, at)
    c >= 48 && c <= 57
  end

  # A send whose last argument is the keywords Hash, as `recv.mid(*a, **h)`.
  #: (value, word, word, ptr) -> value
  def zr_capi_send_kw(recv, mid, argc, argv)
    zr_send(recv, mid, zr_kw_argc(argc, argv), argv)
  end

  # rb_call_super: calls the next method of the C method that runs, with
  # `argc` arguments at `argv`, and its keywords when it got them.
  #: (i32, ptr) -> value
  def rb_call_super(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(argc)
    if Task[zr_task()].c_keywords != 0 && n > 0
      n = zr_kw_argc(n, argv)
    end
    zr_c_result(zr_super(Machine.ptr(0), Task[zr_task()].top, n, argv, Machine.value(QNIL)))
  end

  # rb_get_kwargs: takes the `required` and `optional` keywords that the
  # IDs at `table` name out of `hash` into `values` (undef for a missing
  # optional one), as rb_get_kwargs deletes them from the caller's copy.
  # A negative `optional` (-1 - n) allows other keys. Raises CRuby's
  # `missing keyword` and `unknown keyword` errors. Returns the count of
  # keywords found.
  #: (value, ptr, i32, i32, ptr) -> i32
  def rb_get_kwargs(hash, table, required, optional, values)
    Machine.gates_enter
    zr_c_entered()
    req = Machine.sword(required)
    opt = Machine.sword(optional)
    rest = opt < 0
    if rest
      opt = 0 - 1 - opt
    end
    n = req + opt
    ids = Machine.slot((CAPI_ARGS + 1) * 8)
    if n > CAPI_ARGS
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("too many keywords for rb_get_kwargs"), 35)
    end
    i = 0
    while i < n
      Machine.store64(ids + (i * 8), 0, zr_capi_mid(Machine.load64(table + (i * 8), 0)))
      i += 1
    end
    if hash == QNIL && req > 0
      zr_c_result(zr_kw_missing(Machine.value(QNIL), ids, req))
    end
    if hash != QNIL
      zr_c_result(zr_kw_missing(hash, ids, req))
    end
    found = req
    i = 0
    while i < n
      key = zr_sym(Machine.load64(ids + (i * 8), 0))
      v = hash == QNIL ? Machine.value(QUNDEF) : zr_capi_hash_lookup(hash, key, Machine.value(QUNDEF))
      if v != QUNDEF && i >= req
        found += 1
      end
      if values != 0
        if v != QUNDEF
          zr_c_result(zr_hash_delete_m(hash, key))
        end
        Machine.store64(values + (i * 8), 0, Machine.word(v))
      end
      i += 1
    end
    if !rest && hash != QNIL && RHash[hash].live > (values != 0 ? 0 : found)
      zr_c_result(zr_kw_unknown(hash, ids, n))
    end
    Machine.i32(found)
  end

  # rb_funcallv_kw: rb_funcallv, the last argument the keywords when
  # `kw_splat` is not 0.
  #: (value, word, i32, ptr, i32) -> value
  def rb_funcallv_kw(recv, mid, argc, argv, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_capi_send_maybe_kw(recv, zr_capi_mid(mid), Machine.sword(argc), argv, kw_splat))
  end

  # rb_funcall_with_block: the public method `mid` of `recv` with the
  # Proc `procval` (nil: none) as its block.
  #: (value, word, i32, ptr, value) -> value
  def rb_funcall_with_block(recv, mid, argc, argv, procval)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_dispatch(0, recv, zr_capi_mid(mid), Machine.sword(argc), argv, 2, procval))
  end

  # rb_funcall_with_block_kw: the same, with the keywords Hash last when
  # `kw_splat` says so.
  #: (value, word, i32, ptr, value, i32) -> value
  def rb_funcall_with_block_kw(recv, mid, argc, argv, procval, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(argc)
    if Machine.sword(kw_splat) != 0 && n > 0
      n = zr_kw_argc(n, argv)
    end
    zr_c_result(zr_dispatch(0, recv, zr_capi_mid(mid), n, argv, 2, procval))
  end

  # A send with the keywords Hash last when `kw_splat` (RB_PASS_KEYWORDS)
  # says so.
  #: (value, word, word, ptr, i32) -> value
  def zr_capi_send_maybe_kw(recv, mid, argc, argv, kw_splat)
    zr_capi_send_blk(recv, mid, argc, argv, kw_splat, Machine.value(QNIL))
  end

  # The same, with the block `blk`.
  #: (value, word, word, ptr, i32, value) -> value
  def zr_capi_send_blk(recv, mid, argc, argv, kw_splat, blk)
    if Machine.sword(kw_splat) != 0 && argc > 0
      argc = zr_kw_argc(argc, argv)
    end
    zr_send_blk(recv, mid, argc, argv, blk)
  end

  # rb_undef_method: `klass` has no method `name`. Unlike `undef_method`,
  # a name that no ancestor has is no error, and no hook runs: ruby adds
  # the undef entry as it is (rb_add_method).
  #: (value, ptr) -> void
  def rb_undef_method(klass, name)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(klass)
      zr_c_result(zr_frozen_error(klass))
    end
    zr_method_add(klass, zr_intern(name, zr_cstr_len(name)), 0, 0, KIND_UNDEF, 0, Machine.value(QNIL))
  end

  # rb_f_notimplement: the body of a method that this platform cannot
  # give: it raises CRuby's NotImplementedError, with the method's name.
  #: (i32, ptr, value, value) -> value
  def rb_f_notimplement(argc, argv, recv, marker)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_notimplement()
    Machine.value(QNIL)
  end

  #: () -> void
  def zr_capi_notimplement
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_str(b, zr_capi_id_name(zr_capi_id(FrameMeta[Frame[Task[zr_task()].top].meta].name)))
    zr_buf_push(b, Machine.bytes("() function is unimplemented on this machine"), 44)
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:NotImplementedError)), b))
  end

  # rb_notimplement: NotImplementedError for the C method that runs, as
  # rb_f_notimplement raises it.
  #: () -> void
  def rb_notimplement
    Machine.gates_enter
    zr_c_entered()
    zr_capi_notimplement()
  end

  # rb_enumeratorize, rb_enumeratorize_with_size and its _kw form: the
  # Enumerator of `obj.meth(*argv)`, which RETURN_ENUMERATOR gives when
  # the C method got no block. The last argument is keywords when
  # `kw_splat` says so, and in the forms without it when the C method got
  # keywords, as in ruby. A size function is not kept: the Enumerator's
  # size is nil.
  #: (value, value, i32, ptr) -> value
  def rb_enumeratorize(obj, meth, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_enumeratorize(obj, meth, Machine.sword(argc), argv, Task[zr_task()].c_keywords)
  end

  #: (value, value, i32, ptr, ptr) -> value
  def rb_enumeratorize_with_size(obj, meth, argc, argv, size_fn)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_enumeratorize(obj, meth, Machine.sword(argc), argv, Task[zr_task()].c_keywords)
  end

  #: (value, value, i32, ptr, ptr, i32) -> value
  def rb_enumeratorize_with_size_kw(obj, meth, argc, argv, size_fn, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_enumeratorize(obj, meth, Machine.sword(argc), argv, Machine.sword(kw_splat))
  end

  #: (value, value, word, ptr, word) -> value
  def zr_capi_enumeratorize(obj, meth, argc, argv, keywords)
    count = argc
    kwargs = Machine.value(QNIL)
    if keywords != 0 && argc > 0
      count = argc - 1
      kwargs = Machine.value(Machine.load64(argv + (count * 8), 0))
    else
      kwargs = zr_hash_new()
    end
    args = zr_ary_new(count)
    i = 0
    while i < count
      zr_ary_push(args, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    parts = Machine.slot(40)
    Machine.store64(parts, 0, Machine.word(obj))
    Machine.store64(parts, 8, Machine.word(meth))
    Machine.store64(parts, 16, Machine.word(args))
    Machine.store64(parts, 24, Machine.word(kwargs))
    Machine.store64(parts, 32, QNIL)
    zr_c_result(zr_send(zr_core_class(Machine.id(:Enumerator)), Machine.id(:for), 5, parts))
  end
end
