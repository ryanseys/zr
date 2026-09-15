# Dispatch: the receiver's class chain, then the call through the
# entry's code pointer. A miss is a NoMethodError.

# CRuby's message. A bare identifier (`vcall`) is a NameError, and
# names main as `main`; a `super` with nothing above says so.
sig [Value, Word, Bool, Bool, Word, Ptr] => Value
machine def zr_no_method_from(recv, mid, vcall, from_super, argc, argv)
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
  r = zr_buf_receiver(b, recv)
  return r if r == QUNDEF
  e = zr_exc_new(zr_global(vcall ? G_NAME_ERROR : G_NO_METHOD_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
  zr_exc_detail(e, Machine.id(:receiver), recv)
  if !vcall
    zr_exc_detail(e, Machine.id(:args), zr_ary_of(argc, argv))
  end
  # The locals of the Ruby scope the send was written in, which
  # NameError#local_variables answers, as name_err_init_attr keeps the
  # frame's ISEQ for it.
  source = zr_frame_with_file(Task.top(zr_task()))
  if source != 0
    zr_exc_detail(e, Machine.id(:local_variables), zr_local_names(FrameMeta.locals(Frame.meta(source))))
  end
  zr_raise(e)
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

# `ruby2_keywords`: the methods marked, by their function address.
sig [] => Ptr
machine def zr_ruby2_fns
  Machine.static(:ruby2_fns, IvTab.size)
end

sig [Value, Value] => Value
machine def zr_ruby2_mark_m(klass, name)
  slot = Machine.slot(8)
  r = zr_name_id(name, slot)
  return r if r == QUNDEF
  e = zr_find_method(klass, Machine.load64(slot, 0))
  if e != 0 && MEntry.kind(e) == KIND_BMETHOD
    # A define_method method runs its block, whose function binds the
    # rest, so the mark goes on that.
    zr_ivtab_set(zr_ruby2_fns(), Machine.word(RProc.fn(MEntry.cref(e))), Machine.value(QTRUE))
  elsif e != 0 && MEntry.fn(e) != 0
    zr_ivtab_set(zr_ruby2_fns(), Machine.word(MEntry.fn(e)), Machine.value(QTRUE))
  end
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_ruby2_mark_proc(pr)
  zr_ivtab_set(zr_ruby2_fns(), Machine.word(RProc.fn(pr)), Machine.value(QTRUE))
  pr
end

# A marked method taking keywords into its rest: the Hash carries the
# flag, so a later `*rest` passes it on as keywords again.
sig [Word, Ptr, Ptr] => Void
machine def zr_kw_ruby2_in(argc, argv, fn)
  if zr_kw_take() != 0 && argc > 0 && zr_ivtab_get(zr_ruby2_fns(), Machine.word(fn)) != QUNDEF
    h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    RBasic.set_flags(h, RBasic.flags(h) | FL_RUBY2)
  end
end

# A splat whose last element is a flagged Hash passes it as keywords,
# as a fresh Hash without the flag.
sig [Word, Ptr] => Word
machine def zr_kw_ruby2_out(argc, argv)
  if argc == 0
    return argc
  end
  h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
  if zr_special_p(h) || zr_type(h) != T_HASH || (RBasic.flags(h) & FL_RUBY2) == 0
    return argc
  end
  copy = zr_hash_new()
  zr_hash_update(copy, h)
  Machine.store64(argv + ((argc - 1) * 8), 0, Machine.word(copy))
  zr_kw_argc(argc, argv)
end

sig [] => Word
machine def zr_kw_take
  t = zr_task()
  kw = Task.kw(t)
  Task.set_kw(t, 0)
  kw
end

# Why a call reached `method_missing`, which the base one turns into
# the message: nothing defined the name (called with a receiver, as a
# bare identifier, or explicitly), or the method was private or
# protected.
MISS_IMPLICIT = 1
MISS_VCALL = 2
MISS_EXPLICIT = 3
MISS_PRIVATE = 4
MISS_PROTECTED = 5

# A miss goes to the receiver's `method_missing` with the name in
# front of the arguments; the base one raises as a plain miss does.
sig [Value, Word, Word, Ptr, Value, Word, Word] => Value
machine def zr_method_missing(recv, mid, argc, argv, blk, kw, reason)
  e = zr_find_method(zr_box_view(zr_class_of(recv)), Machine.id(:method_missing))
  if e == 0 || MEntry.fn(e) == Machine.addr(:zr_obj_method_missing)
    return zr_miss_error(recv, mid, reason, argc, argv)
  end
  args = zr_xmalloc((argc + 1) * 8)
  Machine.store64(args, 0, Machine.word(zr_sym(mid)))
  zr_memcpy(args + 8, argv, argc * 8)
  Task.set_missing(zr_task(), reason)
  r = zr_invoke(e, recv, argc + 1, args, blk, kw)
  free(args)
  r
end

sig [Value, Word, Word, Word, Ptr] => Value
machine def zr_miss_error(recv, mid, reason, argc, argv)
  if reason == MISS_PRIVATE
    return zr_hidden_method(recv, mid, VIS_PRIVATE, argc, argv)
  end
  if reason == MISS_PROTECTED
    return zr_hidden_method(recv, mid, VIS_PROTECTED, argc, argv)
  end
  zr_no_method(recv, mid, reason == MISS_VCALL, argc, argv)
end

# `BasicObject#method_missing`: the NoMethodError a miss raises.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_method_missing(recv, argc, argv, cref, blk)
  if argc < 1
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
  end
  m = Machine.value(Machine.load64(argv, 0))
  unless zr_symbol_p(m)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("no id given"), 11)
  end
  t = zr_task()
  reason = Task.missing(t)
  Task.set_missing(t, 0)
  zr_miss_error(recv, zr_sym2id(m), reason, argc - 1, argv + 8)
end

sig [Value, Word, Bool, Word, Ptr] => Value
machine def zr_no_method(recv, mid, vcall, argc, argv)
  zr_no_method_from(recv, mid, vcall, false, argc, argv)
end

# `private method 'x' called for ...`, or protected.
sig [Value, Word, Word, Word, Ptr] => Value
machine def zr_hidden_method(recv, mid, vis, argc, argv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, vis == VIS_PRIVATE ? Machine.bytes("private method '") : Machine.bytes("protected method '"), vis == VIS_PRIVATE ? 16 : 18)
  zr_buf_sym(b, mid)
  zr_buf_push(b, Machine.bytes("' called for "), 13)
  r = zr_buf_receiver(b, recv)
  return r if r == QUNDEF
  e = zr_exc_new(zr_global(G_NO_METHOD_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
  zr_exc_detail(e, Machine.id(:receiver), recv)
  zr_exc_detail(e, Machine.id(:args), zr_ary_of(argc, argv))
  zr_exc_detail(e, Machine.id(:private_call), zr_bool(vis == VIS_PRIVATE))
  zr_raise(e)
end

# How a message names the receiver: main, a special constant, its
# `#<Foo:0x...>` when it has a singleton class, else `an instance of Foo`.
sig [Ptr, Value] => Value
machine def zr_buf_receiver(b, recv)
  if recv == zr_global(G_MAIN)
    zr_buf_push(b, Machine.bytes("main"), 4)
  elsif recv == QNIL
    zr_buf_push(b, Machine.bytes("nil"), 3)
  elsif recv == QTRUE
    zr_buf_push(b, Machine.bytes("true"), 4)
  elsif recv == QFALSE
    zr_buf_push(b, Machine.bytes("false"), 5)
  elsif !zr_special_p(recv) && (zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE)
    zr_buf_push(b, zr_type(recv) == T_CLASS ? Machine.bytes("class ") : Machine.bytes("module "), zr_type(recv) == T_CLASS ? 6 : 7)
    s = zr_inspect(recv)
    return s if s == QUNDEF
    zr_buf_str(b, s)
  elsif !zr_special_p(recv) && zr_singleton_p(RBasic.klass(recv))
    zr_buf_obj_head(b, recv)
    zr_buf_byte(b, 62)
  else
    zr_buf_push(b, Machine.bytes("an instance of "), 15)
    zr_buf_class_of(b, recv)
  end
  Machine.value(QNIL)
end

# Whether a call from the frame on top may reach `e` with `mode` (0 an
# implicit or self receiver, 2 an explicit one, 3 `public_send`, whose
# caller is the frame below its own): a private method only
# implicitly, a protected one when the caller's self is of the owner.
# Answers 0, or the visibility that refused the call.
sig [Ptr, Word] => Word
machine def zr_visibility_refused(e, mode)
  mode = mode & SEND_MODE
  if mode < 2 || MEntry.vis(e) == VIS_PUBLIC
    return 0
  end
  if MEntry.vis(e) == VIS_PROTECTED && mode != 3
    owner = FrameMeta.owner(MEntry.meta(e))
    caller = Task.top(zr_task())
    if caller != 0 && zr_is_a(Frame.self(caller), owner)
      return 0
    end
  end
  MEntry.vis(e)
end

# A send the core library makes to a name outside the protocol CRuby's C
# sends by name: it reaches the core library's own method on a class the
# runtime made, whatever the program wrote over it (zr_find_core_method).
SEND_CORE = 8
SEND_MODE = 7

# `argv` points at `argc` Values the caller keeps rooted. `mode` is 0
# for an implicit or self receiver, 1 for a bare identifier, 2 for an
# explicit receiver, with SEND_CORE added for a send the core library
# makes. A builtin runs under a frame pushed here, so a backtrace names
# it; a compiled method pushes its own. `cc` is the send site's cell
# (cache.rb), which takes the answer, or 0 for a send that has none.
sig [Ptr, Value, Word, Word, Ptr, Word, Value] => Value
machine def zr_dispatch(cc, recv, mid, argc, argv, mode, blk)
  kw = zr_kw_take()
  klass = zr_box_view(zr_class_of(recv))
  e = 0
  if (mode & SEND_CORE) != 0 && zr_core_class_p(klass) && ClassExt.boxed(RClass.ext(klass)) == QNIL
    e = zr_find_core_method(klass, mid)
  end
  if e == 0
    e = zr_find_method(klass, mid)
  end
  if e == 0
    how = mode & SEND_MODE
    return zr_method_missing(recv, mid, argc, argv, blk, kw, how == 1 ? MISS_VCALL : (how == 0 ? MISS_IMPLICIT : MISS_EXPLICIT))
  end
  vis = zr_visibility_refused(e, mode)
  if vis != 0
    return zr_method_missing(recv, mid, argc, argv, blk, kw, vis == VIS_PRIVATE ? MISS_PRIVATE : MISS_PROTECTED)
  end
  if zr_trace_c_p() && (mode & SEND_CORE) == 0 && zr_trace_c_entry_p(e) && zr_trace_c_caller_p()
    return zr_trace_c_invoke(e, klass, recv, mid, argc, argv, blk, kw)
  end
  if cc != 0
    zr_call_cache_fill(cc, klass, e, mode)
  end
  zr_invoke(e, recv, argc, argv, blk, kw)
end

# `super`: the next method named as the frame's is, past the frame's
# owner in the receiver's chain; the frame's block passes on unless
# `blk` is one of its own. In a method `define_method` made, the
# name and owner are the entry's.
sig [Ptr, Word, Ptr, Value] => Value
machine def zr_super(rec, argc, argv, blk)
  kw = zr_kw_take()
  recv = Frame.self(rec)
  entry = zr_bmethod_entry(rec)
  if entry != 0
    owner = FrameMeta.owner(MEntry.meta(entry))
    mid = MEntry.mid(entry)
  else
    meta = zr_method_meta_of(rec)
    if meta == 0
      return zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
    end
    owner = FrameMeta.owner(meta)
    mid = FrameMeta.name(meta)
  end
  k = zr_super_from(rec, recv, owner)
  e = 0
  if k != QNIL && zr_type(k) == T_MODULE && ClassExt.refined(RClass.ext(k)) != QNIL
    # `super` in a refined method reaches what the refinement overrode.
    e = zr_find_method(ClassExt.refined(RClass.ext(k)), mid)
  elsif k != QNIL
    e = zr_find_method(RClass.superclass(k), mid)
  end
  if e == 0
    return zr_no_method_from(recv, mid, false, true, argc, argv)
  end
  zr_invoke(e, recv, argc, argv, blk, kw)
end

# The chain node the method the frame runs in (through its blocks)
# was found on; nil for a frame the kernel pushed.
sig [Ptr] => Value
machine def zr_frame_defined(rec)
  meta = zr_method_meta_of(rec)
  r = rec
  while r != 0 && Frame.meta(r) != meta
    r = Frame.prev(r)
  end
  if r == 0
    return Machine.value(QNIL)
  end
  Frame.defined(r)
end

# The entry of the `define_method` method the frame runs in, or 0.
sig [Ptr] => Ptr
machine def zr_bmethod_entry(rec)
  cref = Frame.cref(rec)
  if cref == QNIL || RCref.eval(cref) == 0
    return 0
  end
  RCref.entry(cref)
end

# The meta of the def the frame is in, through its blocks and evals, or
# 0 in a class body or at the top level.
sig [Ptr] => Ptr
machine def zr_method_meta_of(rec)
  meta = Frame.meta(rec)
  while (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.kind(meta) == KIND_EVAL) && FrameMeta.parent(meta) != 0
    meta = FrameMeta.parent(meta)
  end
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BUILTIN
    return 0
  end
  meta
end

# `defined?(super)`: whether a method waits past this frame's owner.
sig [Ptr] => Value
machine def zr_super_defined(rec)
  entry = zr_bmethod_entry(rec)
  if entry != 0
    owner = FrameMeta.owner(MEntry.meta(entry))
    mid = MEntry.mid(entry)
  else
    meta = zr_method_meta_of(rec)
    if meta == 0
      return Machine.value(QFALSE)
    end
    owner = FrameMeta.owner(meta)
    mid = FrameMeta.name(meta)
  end
  k = zr_super_from(rec, Frame.self(rec), owner)
  if k == QNIL
    return Machine.value(QFALSE)
  end
  zr_bool(zr_find_method(RClass.superclass(k), mid) != 0)
end

# The node a `super` in the frame continues past: the method frame's
# own defining node when it stands for `owner` (a module included
# twice has two), else the first node of `owner` in the receiver's
# chain; nil when there is none.
sig [Ptr, Value, Value] => Value
machine def zr_super_from(rec, recv, owner)
  k = zr_frame_defined(rec)
  if k != QNIL
    return k
  end
  k = zr_class_of(recv)
  while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass.attached(k) == owner))
    k = RClass.superclass(k)
  end
  k
end

# A bare `super` in a block: when the block runs as a method
# `define_method` made, CRuby refuses implicit arguments, whatever def
# the block was written in.
sig [Ptr] => Value
machine def zr_zsuper_in_block(rec)
  if zr_bmethod_entry(rec) != 0
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."), 125)
  end
  Machine.value(QNIL)
end

# A bare `super` with no def around it: refused in a method
# `define_method` made; elsewhere there is no method.
sig [Ptr] => Value
machine def zr_zsuper_outside(rec)
  r = zr_zsuper_in_block(rec)
  return r if r == QUNDEF
  zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
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
    Task.set_mid(zr_task(), MEntry.mid(e))
    if MEntry.from(e) != QNIL
      Task.set_found(zr_task(), MEntry.from(e))
    end
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, MEntry.cref(e), blk)
  end
  # An accessor has no frame, so its arity error is the caller's.
  if MEntry.kind(e) == KIND_ATTR_READER
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    return zr_ivar_get(recv, Machine.word(MEntry.fn(e)))
  end
  if MEntry.kind(e) == KIND_ATTR_WRITER
    if argc != 1
      return zr_wrong_arity(argc, 1)
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
  if MEntry.kind(e) == KIND_MISSING
    return zr_method_missing(recv, MEntry.mid(e), argc, argv, blk, kw, MISS_EXPLICIT)
  end
  rec = Machine.slot(Frame.size)
  t = zr_task()
  # A builtin can run Ruby that calls builtins again, all without a
  # compiled frame between: its frame takes the stack check a compiled
  # prologue makes, before anything is linked.
  if Machine.word(rec) < Machine.word(Task.stack_limit(t))
    return zr_stack_overflow()
  end
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, 0)
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, recv)
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, blk)
  Frame.set_nvalues(rec, 0)
  # The name the builtin was called by, which an alias makes its own: an
  # enumerator it answers records it.
  Frame.set_mid(rec, MEntry.mid(e))
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_lastline(rec, Machine.value(QNIL))
  Frame.set_defined(rec, Machine.value(QNIL))
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
  Frame.set_line(rec, FrameMeta.line(MEntry.meta(e)) | (FrameMeta.node(MEntry.meta(e)) << 32))
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, recv)
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Frame.set_mid(rec, 0)
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_lastline(rec, Machine.value(QNIL))
  Frame.set_defined(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  r = zr_wrong_arity(given, expected)
  Task.set_top(t, Frame.prev(rec))
  r
end

# The kernel's own sends, which have no site and so no cell. Compiled
# Ruby sends through `zr_send_cached` (cache.rb).
sig [Value, Word, Word, Ptr] => Value
machine def zr_send(recv, mid, argc, argv)
  zr_dispatch(0, recv, mid, argc, argv, 0, Machine.value(QNIL))
end

# A send with an explicit receiver: visibility applies.
sig [Value, Word, Word, Ptr] => Value
machine def zr_call(recv, mid, argc, argv)
  zr_dispatch(0, recv, mid, argc, argv, 2, Machine.value(QNIL))
end

sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_send_blk(recv, mid, argc, argv, blk)
  zr_dispatch(0, recv, mid, argc, argv, 0, blk)
end

# `Hash.ruby2_keywords_hash`: a copy carrying the flag, and the test
# for it.
sig [Value] => Value
machine def zr_ruby2_hash_new(h)
  copy = zr_hash_new()
  zr_hash_update(copy, h)
  RBasic.set_flags(copy, RBasic.flags(copy) | FL_RUBY2)
  copy
end

sig [Value] => Value
machine def zr_ruby2_hash_p(h)
  zr_bool(!zr_special_p(h) && zr_type(h) == T_HASH && (RBasic.flags(h) & FL_RUBY2) != 0)
end

# Preemption. A green thread that only computes reaches no blocking
# call, so nothing else would ever run. Every loop back edge in
# compiled Ruby calls here; once the count runs out the running thread
# hands the turn on. Thread arms the receiver and the message when a
# second thread appears, so a one-thread program pays a count alone.
PREEMPT_TICKS = 20_000

sig [Value, Value] => Value
machine def zr_preempt_arm(receiver, message)
  Machine.store64(Machine.static(:preempt_mid, 8), 0, zr_sym2id(message))
  Machine.store64(Machine.static(:preempt_to, 8), 0, Machine.word(receiver))
  Machine.value(QNIL)
end

# Whether a second thread ever started. Until one does, every task is
# alone, and IO need not ask the scheduler before a system call.
sig [] => Value
machine def zr_threaded
  zr_bool(Machine.load64(Machine.static(:preempt_to, 8), 0) != 0)
end

sig [] => Value
machine def zr_preempt
  count = Machine.static(:preempt_count, 8)
  n = Machine.load64(count, 0) - 1
  if n > 0
    Machine.store64(count, 0, n)
    return Machine.value(QNIL)
  end
  zr_preempt_expired()
end

# The count ran out: it starts again, the handlers of any signal that
# came run, and the turn goes on if a second thread armed the
# preemption. Compiled back edges count down inline and call here only
# when the count reaches zero, which a caught signal makes it do.
sig [] => Value
machine def zr_preempt_expired
  Machine.store64(Machine.static(:preempt_count, 8), 0, PREEMPT_TICKS)
  if zr_trap_check() == QUNDEF
    return Machine.value(QUNDEF)
  end
  mid = Machine.load64(Machine.static(:preempt_mid, 8), 0)
  if mid == 0
    return Machine.value(QNIL)
  end
  zr_preempt_send(mid)
end

# The turn goes on through the armed receiver, and never while this
# task is already inside one of those sends: the scheduler runs
# compiled Ruby of its own, back edges and all.
sig [Word] => Value
machine def zr_preempt_send(mid)
  busy = Machine.static(:preempt_busy, 8)
  t = Machine.word(zr_task())
  if Machine.load64(busy, 0) == t
    return Machine.value(QNIL)
  end
  Machine.store64(busy, 0, t)
  r = zr_send(Machine.value(Machine.load64(Machine.static(:preempt_to, 8), 0)), mid, 0, Machine.ptr(0))
  Machine.store64(busy, 0, 0)
  r
end

# Whether `v` takes `mid`, as rb_check_funcall decides before a
# conversion calls it: a respond_to? of the program's own that says no
# refuses; a method answers; else a respond_to_missing? of the program's
# own that says yes lets method_missing answer. QUNDEF when a hook
# raised.
sig [Value, Word] => Value
machine def zr_check_funcall(v, mid)
  klass = zr_class_of(v)
  asks = zr_find_method(klass, Machine.id(:respond_to?))
  if asks != 0 && MEntry.core(asks) == 0
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_sym(mid)))
    Machine.store64(argv, 8, QTRUE)
    r = zr_send(v, Machine.id(:respond_to?), 2, argv)
    return r if r == QUNDEF
    if r == QNIL || r == QFALSE
      return Machine.value(QFALSE)
    end
  end
  if zr_find_method(klass, mid) != 0
    return Machine.value(QTRUE)
  end
  missing = zr_find_method(klass, Machine.id(:respond_to_missing?))
  if missing == 0 || MEntry.core(missing) != 0
    return Machine.value(QFALSE)
  end
  argv = Machine.slot(16)
  Machine.store64(argv, 0, Machine.word(zr_sym(mid)))
  Machine.store64(argv, 8, QTRUE)
  r = zr_send(v, Machine.id(:respond_to_missing?), 2, argv)
  return r if r == QUNDEF
  zr_bool(r != QNIL && r != QFALSE)
end
