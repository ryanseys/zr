# Dispatch: the receiver's class chain, then the call through the
# entry's code pointer. A miss is a NoMethodError.

# CRuby's message. A bare identifier (`vcall`) is a NameError, and
# names main as `main`.
sig [Value, Word, Bool] => Value
machine def zr_no_method(recv, mid, vcall)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if vcall
    zr_buf_push(b, Machine.bytes("undefined local variable or method '"), 36)
  else
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
  end
  zr_buf_sym(b, mid)
  zr_buf_push(b, Machine.bytes("' for "), 6)
  if recv == zr_global(G_MAIN)
    if vcall
      zr_buf_push(b, Machine.bytes("main"), 4)
    else
      zr_buf_push(b, Machine.bytes("main:Object"), 11)
    end
  elsif recv == QNIL
    zr_buf_push(b, Machine.bytes("nil"), 3)
  elsif recv == QTRUE
    zr_buf_push(b, Machine.bytes("true"), 4)
  elsif recv == QFALSE
    zr_buf_push(b, Machine.bytes("false"), 5)
  else
    zr_buf_push(b, Machine.bytes("an instance of "), 15)
    zr_buf_str(b, RClass.name(zr_class_of(recv)))
  end
  zr_raise_buf(zr_global(vcall ? G_NAME_ERROR : G_NO_METHOD_ERROR), b)
end

sig [Word, Word] => Value
machine def zr_wrong_arity(given, expected)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("wrong number of arguments (given "), 33)
  zr_buf_long(b, given)
  zr_buf_push(b, Machine.bytes(", expected "), 11)
  zr_buf_long(b, expected)
  zr_buf_byte(b, 41)
  zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
end

# `argv` points at `argc` Values the caller keeps rooted.
# A builtin runs under a frame pushed here, so a backtrace names it; a
# compiled method pushes its own.
sig [Value, Word, Word, Ptr, Bool] => Value
machine def zr_dispatch(recv, mid, argc, argv, vcall)
  e = zr_find_method(zr_class_of(recv), mid)
  if e == 0
    return zr_no_method(recv, mid, vcall)
  end
  if MEntry.kind(e) == KIND_DEF
    arity = MEntry.arity(e)
    if arity >= 0 && argc != arity
      return zr_wrong_arity_in(argc, arity, e, recv)
    end
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, MEntry.cref(e))
  end
  if MEntry.kind(e) == KIND_ATTR_READER
    if argc != 0
      return zr_wrong_arity_in(argc, 0, e, recv)
    end
    return zr_ivar_get(recv, Machine.word(MEntry.fn(e)))
  end
  if MEntry.kind(e) == KIND_ATTR_WRITER
    if argc != 1
      return zr_wrong_arity_in(argc, 1, e, recv)
    end
    return zr_ivar_set(recv, Machine.word(MEntry.fn(e)), Machine.value(Machine.load64(argv, 0)))
  end
  rec = Machine.slot(Frame.size)
  t = zr_task()
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, 0)
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, recv)
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Task.set_top(t, rec)
  arity = MEntry.arity(e)
  if arity >= 0 && argc != arity
    r = zr_wrong_arity(argc, arity)
  else
    r = Machine.call(:method, MEntry.fn(e), recv, argc, argv, Machine.value(QNIL))
  end
  Task.set_top(t, Frame.prev(rec))
  r
end

# An arity error in a compiled method is raised under that method's
# frame, as CRuby's backtrace shows it.
sig [Word, Word, Ptr, Value] => Value
machine def zr_wrong_arity_in(given, expected, e, recv)
  rec = Machine.slot(Frame.size)
  t = zr_task()
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, FrameMeta.line(MEntry.meta(e)))
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, recv)
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Task.set_top(t, rec)
  r = zr_wrong_arity(given, expected)
  Task.set_top(t, Frame.prev(rec))
  r
end

sig [Value, Word, Word, Ptr] => Value
machine def zr_send(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, false)
end

# A bare identifier: the same dispatch, a NameError on a miss.
sig [Value, Word, Word, Ptr] => Value
machine def zr_vcall(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, true)
end
