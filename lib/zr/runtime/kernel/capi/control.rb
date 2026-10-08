module Zr::Kern
  # The C API's exceptions and its ways to stop an unwind in C: rb_raise
  # and its kind leap out of C (zr_c_unwind); rb_protect, rb_ensure and
  # rb_rescue call a C function in a C frame record of their own, so a
  # leap inside it ends at them.

  # CRuby's tags for the kind of an unwind, as rb_protect gives `*state`.
  TAG_RETURN = 1
  TAG_BREAK = 2
  TAG_RAISE = 6
  TAG_THROW = 7

  # rb_exc_raise: raises the exception `exc`.
  #: (value) -> void
  def rb_exc_raise(exc)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_raise(exc))
  end

  # rb_exc_new_str: a new exception of `klass` with the message `message`,
  # through its initialize.
  #: (value, value) -> value
  def rb_exc_new_str(klass, message)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_exc_new_str(klass, message))
  end

  # rb_exc_new: the same, with the message's `len` bytes.
  #: (value, ptr, word) -> value
  def rb_exc_new(klass, bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_exc_new_str(klass, zr_str_new(bytes, len)))
  end

  #: (value, ptr) -> value
  def rb_exc_new_cstr(klass, text)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_exc_new_str(klass, zr_str_new(text, zr_cstr_len(text))))
  end

  # rb_errinfo: the exception that is being handled ($!).
  #: () -> value
  def rb_errinfo
    Machine.gates_enter
    zr_c_entered()
    Task[zr_task()].errinfo
  end

  # rb_set_errinfo: sets $!. Nil also drops an unwind that rb_protect
  # stopped, as clearing ruby's errinfo ends it.
  #: (value) -> void
  def rb_set_errinfo(err)
    Machine.gates_enter
    zr_c_entered()
    t = zr_task()
    Task[t].errinfo = err
    if err == QNIL
      Task[t].parked = Machine.value(QNIL)
    end
  end

  # The data words that these functions give the C functions are C's: a
  # Value, or as often the address of a struct, so none is a root.

  # rb_protect: calls `fn(data)`, and stops any unwind out of it. `*state`
  # is 0, or the unwind's tag, which rb_jump_tag resumes it with; then the
  # result is nil.
  #: (ptr, word, ptr) -> value
  def rb_protect(fn, data, state)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, data)
    zr_capi_protected(Machine.value(zr_call_c(fn, argv, 1)), state)
  end

  # The result `r` of a protected call: undef parks its unwind, whose tag
  # goes to `*state` (0 for none) and gives nil.
  #: (value, ptr) -> value
  def zr_capi_protected(r, state)
    tag = 0
    if r == QUNDEF
      tag = zr_capi_park()
      r = Machine.value(QNIL)
    end
    if state != 0
      Machine.store32(state, 0, Machine.i32(tag))
    end
    r
  end

  # rb_jump_tag: resumes the unwind that rb_protect stopped.
  #: (i32) -> void
  def rb_jump_tag(state)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_unpark()
    zr_c_unwind()
  end

  # rb_ensure: calls `body(data1)`, then the ensure function whatever the body
  # did (`ensure_fn(data2)`), then goes on with the body's unwind, if it
  # had one.
  #: (ptr, word, ptr, word) -> value
  def rb_ensure(body, data1, ensure_fn, data2)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, data1)
    r = Machine.value(zr_call_c(body, argv, 1))
    left = Machine.value(QNIL)
    if r == QUNDEF
      zr_capi_park()
      left = Task[zr_task()].parked
      Task[zr_task()].parked = Machine.value(QNIL)
    end
    Machine.store64(argv, 0, data2)
    if zr_call_c(ensure_fn, argv, 1) == QUNDEF
      zr_c_unwind()
    end
    if r == QUNDEF
      Task[zr_task()].parked = left
      zr_capi_unpark()
      zr_c_unwind()
    end
    r
  end

  # rb_rescue: calls `body(data1)`; a StandardError that it raises calls
  # `rescue_fn(data2, exception)` instead, whose result it gives.
  #: (ptr, word, ptr, word) -> value
  def rb_rescue(body, data1, rescue_fn, data2)
    Machine.gates_enter
    zr_c_entered()
    classes = Machine.slot(16)
    Machine.store64(classes, 0, Machine.word(zr_global(G_STANDARD_ERROR)))
    Machine.store64(classes, 8, 0)
    zr_capi_rescue(body, data1, rescue_fn, data2, classes)
  end

  # rb_rescue2: the same for the exception classes that follow, up to a 0.
  #: (ptr, word, ptr, word) -> value
  def rb_rescue2(body, data1, rescue_fn, data2)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    classes = Machine.slot((CAPI_ARGS + 1) * 8)
    n = 0
    klass = zr_va_next_word(list)
    while klass != 0 && n < CAPI_ARGS
      Machine.store64(classes + (n * 8), 0, klass)
      n += 1
      klass = zr_va_next_word(list)
    end
    Machine.store64(classes + (n * 8), 0, 0)
    zr_capi_rescue(body, data1, rescue_fn, data2, classes)
  end

  # rb_vrescue2: `classes` is a 0-terminated list. With no rescue
  # function, a rescued call gives nil.
  #: (ptr, word, ptr, word, ptr) -> value
  def zr_capi_rescue(body, data1, rescue_fn, data2, classes)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, data1)
    r = Machine.value(zr_call_c(body, argv, 1))
    if r != QUNDEF
      return r
    end
    t = zr_task()
    exc = Task[t].pending
    if Task[t].pending_kind != PENDING_RAISE || !zr_capi_rescues_p(exc, classes)
      zr_c_unwind()
    end
    # $! is the exception while the rescue function runs, and what it was
    # before after it, as rb_vrescue2 keeps it.
    before = Task[t].errinfo
    zr_capi_park()
    Task[t].parked = Machine.value(QNIL)
    rescued = Machine.value(QNIL)
    if rescue_fn != 0
      Machine.store64(argv, 0, data2)
      Machine.store64(argv, 8, Machine.word(exc))
      rescued = zr_c_result(Machine.value(zr_call_c(rescue_fn, argv, 2)))
    end
    Task[zr_task()].errinfo = before
    rescued
  end

  # Whether `exc` is a kind of one of the classes in the 0-terminated list.
  #: (value, ptr) -> bool
  def zr_capi_rescues_p(exc, classes)
    while Machine.load64(classes, 0) != 0
      if zr_is_a(exc, Machine.value(Machine.load64(classes, 0)))
        return true
      end
      classes += 8
    end
    false
  end

  # Takes the task's pending unwind and keeps it in `Task.parked`, as
  # CRuby keeps it in errinfo and the tag. Returns the unwind's tag. A
  # raise also sets $!.
  #: () -> word
  def zr_capi_park
    t = zr_task()
    kind = Task[t].pending_kind
    left = zr_ary_new(6)
    zr_ary_push(left, Task[t].pending)
    zr_ary_push(left, Task[t].throw_tag)
    zr_ary_push(left, zr_fix(kind))
    zr_ary_push(left, zr_fix(Machine.word(Task[t].pending_home)))
    zr_ary_push(left, zr_fix(Task[t].pending_site))
    zr_ary_push(left, zr_fix(Machine.word(Task[t].pending_from)))
    Task[t].parked = left
    if kind == PENDING_RAISE
      Task[t].errinfo = Task[t].pending
    end
    Task[t].pending = Machine.value(QNIL)
    Task[t].throw_tag = Machine.value(QNIL)
    if kind == PENDING_BREAK
      return TAG_BREAK
    end
    if kind == PENDING_RETURN
      return TAG_RETURN
    end
    if kind == PENDING_THROW
      return TAG_THROW
    end
    TAG_RAISE
  end

  # Makes the parked unwind the task's pending one again.
  #: () -> void
  def zr_capi_unpark
    t = zr_task()
    left = Task[t].parked
    if left == QNIL
      zr_bug(Machine.bytes("[BUG] rb_jump_tag with no unwind that rb_protect stopped\n"), 57)
    end
    Task[t].parked = Machine.value(QNIL)
    Task[t].pending = zr_ary_at(left, 0)
    Task[t].throw_tag = zr_ary_at(left, 1)
    Task[t].pending_kind = zr_fix2long(zr_ary_at(left, 2))
    Task[t].pending_home = Machine.ptr(zr_fix2long(zr_ary_at(left, 3)))
    Task[t].pending_site = zr_fix2long(zr_ary_at(left, 4))
    Task[t].pending_from = Machine.ptr(zr_fix2long(zr_ary_at(left, 5)))
  end

  # rb_catch_obj: `catch(tag) { |tag| ... }` with the C block function
  # `fn` (rb_block_call's form) as the block; a throw to `tag` gives its
  # value. rb_catch: the same with the Symbol of the C string `tag`.
  #: (value, ptr, word) -> value
  def rb_catch_obj(tag, fn, data)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_catch(tag, zr_capi_cblock_new(fn, data)))
  end

  #: (ptr, ptr, word) -> value
  def rb_catch(tag, fn, data)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_catch(zr_sym(zr_intern(tag, zr_cstr_len(tag))), zr_capi_cblock_new(fn, data)))
  end

  # rb_throw_obj and rb_throw: `throw(tag, value)`, which raises
  # UncaughtThrowError when no catch waits for `tag`.
  #: (value, value) -> void
  def rb_throw_obj(tag, value)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_throw(tag, value)
  end

  #: (ptr, value) -> void
  def rb_throw(tag, value)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_throw(zr_sym(zr_intern(tag, zr_cstr_len(tag))), value)
  end

  #: (value, value) -> void
  def zr_capi_throw(tag, value)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(tag))
    Machine.store64(args, 8, Machine.word(value))
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:throw), 2, args))
  end
end
