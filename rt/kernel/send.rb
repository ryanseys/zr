# Dispatch: the receiver's class chain, then the call through the
# entry's code pointer. A miss is a NoMethodError.

# CRuby's message. A bare identifier (`vcall`) is a NameError, and
# names main as `main`; a `super` with nothing above says so.
sig [Value, Word, Bool, Bool] => Value
machine def zr_no_method_from(recv, mid, vcall, from_super)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if from_super
    zr_buf_push(b, Machine.bytes("super: no superclass method '"), 29)
  elsif vcall
    zr_buf_push(b, Machine.bytes("undefined local variable or method '"), 36)
  else
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
  end
  zr_buf_sym(b, mid)
  zr_buf_push(b, Machine.bytes("' for "), 6)
  r = zr_buf_receiver(b, recv, vcall)
  return r if r == QUNDEF
  zr_raise_buf(zr_global(vcall ? G_NAME_ERROR : G_NO_METHOD_ERROR), b)
end

# `wrong number of arguments (given 3, expected 1..2)`: `max` is the
# same as `min` for an exact count, and -1 for no limit. A def with
# required keywords names them after the count.
sig [Word, Word, Word, Ptr, Word] => Value
machine def zr_wrong_arity_kw(given, min, max, ids, nkw)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("wrong number of arguments (given "), 33)
  zr_buf_long(b, given)
  zr_buf_push(b, Machine.bytes(", expected "), 11)
  zr_buf_long(b, min)
  if max < 0
    zr_buf_byte(b, 43)
  elsif max != min
    zr_buf_push(b, Machine.bytes(".."), 2)
    zr_buf_long(b, max)
  end
  if nkw > 0
    zr_buf_push(b, Machine.bytes("; required keyword"), 18)
    if nkw > 1
      zr_buf_byte(b, 115)
    end
    zr_buf_push(b, Machine.bytes(": "), 2)
    i = 0
    while i < nkw
      if i > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      zr_buf_sym(b, Machine.load64(ids + (i * 8), 0))
      i += 1
    end
  end
  zr_buf_byte(b, 41)
  zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
end

sig [Word, Word] => Value
machine def zr_wrong_arity(given, expected)
  zr_wrong_arity_kw(given, expected, expected, 0, 0)
end

sig [Word, Word, Word] => Value
machine def zr_wrong_arity_range(given, min, max)
  zr_wrong_arity_kw(given, min, max, 0, 0)
end

sig [Word, Word] => Value
machine def zr_wrong_arity_min(given, min)
  zr_wrong_arity_kw(given, min, 0 - 1, 0, 0)
end

# A call passing keywords sets the task's flag right before the send;
# the callee that declares keywords takes it, and any other sees the
# keywords as a trailing Hash.
sig [] => Void
machine def zr_kw_pass
  Task.set_kw(zr_task(), 1)
end

# The count a send passes when its last argument is the keywords
# Hash: an empty one, as `**{}` makes, is not passed at all.
sig [Word, Ptr] => Word
machine def zr_kw_argc(argc, argv)
  h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
  if RHash.live(h) == 0
    return argc - 1
  end
  zr_kw_pass()
  argc
end

sig [] => Word
machine def zr_kw_take
  t = zr_task()
  kw = Task.kw(t)
  Task.set_kw(t, 0)
  kw
end

sig [Value, Word, Bool] => Value
machine def zr_no_method(recv, mid, vcall)
  zr_no_method_from(recv, mid, vcall, false)
end

# `private method 'x' called for ...`, or protected.
sig [Value, Word, Word] => Value
machine def zr_hidden_method(recv, mid, vis)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, vis == VIS_PRIVATE ? Machine.bytes("private method '") : Machine.bytes("protected method '"), vis == VIS_PRIVATE ? 16 : 18)
  zr_buf_sym(b, mid)
  zr_buf_push(b, Machine.bytes("' called for "), 13)
  zr_buf_receiver(b, recv, false)
  zr_raise_buf(zr_global(G_NO_METHOD_ERROR), b)
end

# How a message names the receiver: main, a special constant, its
# `#<Foo:0x...>` when it has a singleton class, else `an instance of Foo`.
sig [Ptr, Value, Bool] => Value
machine def zr_buf_receiver(b, recv, vcall)
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
  elsif !zr_special_p(recv) && (zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE)
    zr_buf_push(b, zr_type(recv) == T_CLASS ? Machine.bytes("class ") : Machine.bytes("module "), zr_type(recv) == T_CLASS ? 6 : 7)
    s = zr_send(recv, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_buf_str(b, s)
  elsif !zr_special_p(recv) && zr_singleton_p(RBasic.klass(recv))
    zr_buf_obj_head(b, recv)
    zr_buf_byte(b, 62)
  else
    zr_buf_push(b, Machine.bytes("an instance of "), 15)
    zr_buf_str(b, zr_class_name_of(recv))
  end
  Machine.value(QNIL)
end

# Whether a call from the frame on top may reach `e` with `mode` (0 an
# implicit or self receiver, 2 an explicit one): a private method only
# implicitly, a protected one when the caller's self is of the owner.
sig [Ptr, Value, Word, Word] => Value
machine def zr_check_visibility(e, recv, mid, mode)
  if mode != 2 || MEntry.vis(e) == VIS_PUBLIC
    return Machine.value(QNIL)
  end
  if MEntry.vis(e) == VIS_PROTECTED
    owner = FrameMeta.owner(MEntry.meta(e))
    if zr_is_a(Frame.self(Task.top(zr_task())), owner)
      return Machine.value(QNIL)
    end
  end
  zr_hidden_method(recv, mid, MEntry.vis(e))
end

# `argv` points at `argc` Values the caller keeps rooted. `mode` is 0
# for an implicit or self receiver, 1 for a bare identifier, 2 for an
# explicit receiver. A builtin runs under a frame pushed here, so a
# backtrace names it; a compiled method pushes its own.
sig [Value, Word, Word, Ptr, Word, Value] => Value
machine def zr_dispatch(recv, mid, argc, argv, mode, blk)
  kw = zr_kw_take()
  e = zr_find_method(zr_class_of(recv), mid)
  if e == 0
    return zr_no_method(recv, mid, mode == 1)
  end
  r = zr_check_visibility(e, recv, mid, mode)
  return r if r == QUNDEF
  zr_invoke(e, recv, argc, argv, blk, kw)
end

# `super`: the next method named as the frame's is, past the frame's
# owner in the receiver's chain; the frame's block passes on unless
# `blk` is one of its own.
sig [Ptr, Word, Ptr, Value] => Value
machine def zr_super(rec, argc, argv, blk)
  kw = zr_kw_take()
  meta = Frame.meta(rec)
  while FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN
    meta = FrameMeta.parent(meta)
  end
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BUILTIN
    zr_bug(Machine.bytes("super inside define_method or an eval block is not implemented yet\n"), 66)
  end
  owner = FrameMeta.owner(meta)
  mid = FrameMeta.name(meta)
  recv = Frame.self(rec)
  k = zr_class_of(recv)
  while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass.attached(k) == owner))
    k = RClass.superclass(k)
  end
  e = 0
  if k != QNIL
    e = zr_find_method(RClass.superclass(k), mid)
  end
  if e == 0
    return zr_no_method_from(recv, mid, false, true)
  end
  zr_invoke(e, recv, argc, argv, blk, kw)
end

# `defined?(super)`: whether a method waits past this frame's owner.
sig [Ptr] => Value
machine def zr_super_defined(rec)
  meta = Frame.meta(rec)
  while FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN
    meta = FrameMeta.parent(meta)
  end
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BUILTIN
    return Machine.value(QFALSE)
  end
  owner = FrameMeta.owner(meta)
  k = zr_class_of(Frame.self(rec))
  while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass.attached(k) == owner))
    k = RClass.superclass(k)
  end
  if k == QNIL
    return Machine.value(QFALSE)
  end
  zr_bool(zr_find_method(RClass.superclass(k), FrameMeta.name(meta)) != 0)
end

# The call through the entry `e`: a compiled def gets the keywords flag
# back and pushes its own frame; a builtin runs under one pushed here.
sig [Ptr, Value, Word, Ptr, Value, Word] => Value
machine def zr_invoke(e, recv, argc, argv, blk, kw)
  if MEntry.kind(e) == KIND_DEF
    arity = MEntry.arity(e)
    if arity >= 0 && argc != arity
      return zr_wrong_arity_in(argc, arity, e, recv)
    end
    Task.set_kw(zr_task(), kw)
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, MEntry.cref(e), blk)
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
  if MEntry.kind(e) == KIND_FRAMELESS
    Task.set_kw(zr_task(), kw)
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, Machine.value(QNIL), blk)
  end
  if MEntry.kind(e) == KIND_BMETHOD
    Task.set_kw(zr_task(), kw)
    return zr_bmethod_call(e, recv, argc, argv, blk)
  end
  rec = Machine.slot(Frame.size)
  t = zr_task()
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, 0)
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, recv)
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, blk)
  Frame.set_nvalues(rec, 0)
  Task.set_top(t, rec)
  Task.set_kw(t, kw)
  arity = MEntry.arity(e)
  if arity >= 0 && argc != arity
    r = zr_wrong_arity(argc, arity)
  else
    r = Machine.call(:method, MEntry.fn(e), recv, argc, argv, Machine.value(QNIL), blk)
  end
  Task.set_kw(t, 0)
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
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Task.set_top(t, rec)
  r = zr_wrong_arity(given, expected)
  Task.set_top(t, Frame.prev(rec))
  r
end

sig [Value, Word, Word, Ptr] => Value
machine def zr_send(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, 0, Machine.value(QNIL))
end

# A send with an explicit receiver: visibility applies.
sig [Value, Word, Word, Ptr] => Value
machine def zr_call(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, 2, Machine.value(QNIL))
end

sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_call_blk(recv, mid, argc, argv, blk)
  zr_dispatch(recv, mid, argc, argv, 2, blk)
end

sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_send_blk(recv, mid, argc, argv, blk)
  zr_dispatch(recv, mid, argc, argv, 0, blk)
end

# A bare identifier: the same dispatch, a NameError on a miss.
sig [Value, Word, Word, Ptr] => Value
machine def zr_vcall(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, 1, Machine.value(QNIL))
end
