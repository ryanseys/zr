# Dispatch: a lookup in the receiver's ancestor list, then a call
# through the method entry's code pointer. A miss raises NoMethodError.

# Raises the error for a miss, with CRuby's message. A bare identifier
# (`vcall`) raises NameError and shows main as `main`. A `super` with no
# method above it has its own message.
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
  # Keep the locals of the Ruby scope that contains the send, for
  # NameError#local_variables. CRuby's name_err_init_attr keeps the
  # frame's ISEQ for the same purpose.
  source = zr_frame_with_file(Task.top(zr_task()))
  if source != 0
    zr_exc_detail(e, Machine.id(:local_variables), zr_local_names(FrameMeta.locals(Frame.meta(source))))
  end
  zr_raise(e)
end

# Raises `wrong number of arguments (given 3, expected 1..2)`. `max` is
# equal to `min` for an exact count, and -1 for no limit. For a def with
# required keywords, the message gives them after the count.
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

# A call that passes keywords sets the task's keyword word immediately
# before the send. The word is 1 for a flagged trailing Hash. Otherwise
# it is the address (above 1) of a table: the count, then the ids. The
# table's values are the call's last arguments. This is how `k: v` pairs
# with plain Symbol keys go to the callee. A compiled def reads the word
# in its prologue. A def that declares keywords reads the table's values
# by position (`zr_kw_shape`). A def that declares none makes the values
# one Hash argument (`zr_kw_undeclared`). A builtin, an accessor or a
# `method_missing` gets a flagged Hash, made from the table
# (`zr_kw_tab_in`).
sig [] => Void
machine def zr_kw_pass
  Task.set_kw(zr_task(), 1)
end

# Puts the table's values into one Hash, in place of the first value.
# Returns the new argument count.
sig [Word, Word, Ptr] => Word
machine def zr_kw_tab_in(tab, argc, argv)
  n = Machine.load64(tab, 0)
  count = argc - n
  h = zr_hash_new()
  i = 0
  while i < n
    zr_hash_store(h, zr_sym(Machine.load64(tab + 8 + (i * 8), 0)), Machine.value(Machine.load64(argv + ((count + i) * 8), 0)))
    i += 1
  end
  Machine.store64(argv + (count * 8), 0, Machine.word(h))
  count + 1
end

# Returns the argument count of a send whose last argument is the
# keywords Hash. An empty Hash, as from `**{}`, is not passed.
sig [Word, Ptr] => Word
machine def zr_kw_argc(argc, argv)
  h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
  if RHash.live(h) == 0
    return argc - 1
  end
  zr_kw_pass()
  argc
end

# `ruby2_keywords`: the marked methods, by their function address.
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
    # A define_method method runs its block, and the block's function
    # binds the rest argument, so the mark goes on the block's function.
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

# For a def or block that declares no keywords, called with the keyword
# word `kw` set. A table's values become one Hash argument. A
# `ruby2_keywords` rest (the function `fn`, 0 for no rest) flags the Hash
# that it gets, so a later `*rest` passes it as keywords again. Returns
# the new argument count.
sig [Word, Word, Ptr, Ptr] => Word
machine def zr_kw_undeclared(kw, argc, argv, fn)
  if kw > 1
    argc = zr_kw_tab_in(kw, argc, argv)
  end
  if fn != 0 && argc > 0 && zr_ivtab_get(zr_ruby2_fns(), Machine.word(fn)) != QUNDEF
    h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    RBasic.set_flags(h, RBasic.flags(h) | FL_RUBY2)
  end
  argc
end

# A splat whose last element is a flagged Hash passes that Hash as
# keywords, in a new Hash without the flag.
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

# Why a call went to `method_missing`. The base `method_missing` uses it
# for the message. Either no method has the name (called with an
# implicit receiver, as a bare identifier, or with an explicit
# receiver), or the method is private or protected.
MISS_IMPLICIT = 1
MISS_VCALL = 2
MISS_EXPLICIT = 3
MISS_PRIVATE = 4
MISS_PROTECTED = 5
MISS_SUPER = 6

# Sends a miss to the receiver's `method_missing`, with the name before
# the arguments. The base `method_missing` raises as a plain miss does.
sig [Value, Word, Word, Ptr, Value, Word, Word] => Value
machine def zr_method_missing(recv, mid, argc, argv, blk, kw, reason)
  if kw > 1
    argc = zr_kw_tab_in(kw, argc, argv)
    kw = 1
  end
  e = zr_find_method(zr_box_view(zr_class_of(recv)), Machine.id(:method_missing))
  if e == 0 || MEntry.fn(e) == Machine.addr(:zr_obj_method_missing)
    return zr_miss_error(recv, mid, reason, argc, argv)
  end
  args = zr_xmalloc((argc + 1) * 8)
  Machine.store64(args, 0, Machine.word(zr_sym(mid)))
  zr_memcpy(args + 8, argv, argc * 8)
  Task.set_missing(zr_task(), reason)
  r = zr_invoke(e, recv, argc + 1, args, blk, kw)
  zr_xfree(args)
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
  if reason == MISS_SUPER
    return zr_no_method_from(recv, mid, false, true, argc, argv)
  end
  zr_no_method(recv, mid, reason == MISS_VCALL, argc, argv)
end

# `BasicObject#method_missing`: raises the NoMethodError for a miss.
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

# Raises `private method 'x' called for ...`, or the protected form.
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
  # `private_call?` is true when the call had no explicit receiver. A
  # call that finds a private or protected method always has one.
  zr_exc_detail(e, Machine.id(:private_call), Machine.value(QFALSE))
  zr_raise(e)
end

# Writes how a message shows the receiver: main, a special constant,
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

# Whether a call from the top frame can call `e` with `mode`. `mode` is 0
# for an implicit or self receiver, 2 for an explicit receiver, and 3 for
# `public_send` (its caller is the frame below its own). A private method
# needs an implicit receiver. A protected method needs a caller whose
# self is an instance of the owner. Returns 0, or the visibility that
# stopped the call.
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

# A send from the core library, to a name outside the protocol that
# CRuby's C code sends by name. It finds the core library's own method on
# a class that the runtime made, also when the program redefines the
# method (zr_find_core_method).
SEND_CORE = 8
SEND_MODE = 7
# A send written under `using`. The site sets its own active
# refinements on the task before each send (the lowering's `activate`,
# inline), and clears them after. Thus at that site the lookup result
# depends only on the class and the stamp, and its cache entries can
# keep it. The site checks its cache entry and takes an operator's fast
# path, as any site does. A refinement's definition increments the
# stamp, as any definition does, and closes the gate of the name that it
# refines (zr_method_add_row). A `using` also increments the stamp.
SEND_USING = 16

# `argv` points at `argc` Values that the caller keeps rooted. `mode` is
# 0 for an implicit or self receiver, 1 for a bare identifier, 2 for an
# explicit receiver, plus SEND_CORE for a send from the core library. A
# builtin runs under a frame that this pushes, so a backtrace shows it.
# A compiled method pushes its own frame. `cc` is the send site's cache
# entry (cache.rb), which gets the result, or 0 for a send without one.
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
  if zr_trace_sends_p() && (mode & SEND_CORE) == 0 && zr_trace_c_caller_p()
    if zr_trace_ruby_entry_p(e)
      return zr_trace_send_invoke(e, recv, mid, argc, argv, blk, kw, TRACE_CALL)
    end
    if zr_trace_c_entry_p(e)
      return zr_trace_send_invoke(e, recv, mid, argc, argv, blk, kw, TRACE_C_CALL)
    end
  end
  if cc != 0
    zr_call_cache_fill(cc, klass, e, mid, mode, argc)
  end
  r = zr_invoke(e, recv, argc, argv, blk, kw)
  # A site activates refinements for this send only: for the lookup, and
  # for a builtin such as `send` or `respond_to?` that uses them. A site
  # that checks its own cache entry never uses them.
  Task.set_refine(zr_task(), Machine.value(QNIL))
  r
end

# `super`: calls the next method with the frame's method name, after the
# frame's owner in the receiver's ancestor list. The frame's block goes
# to the callee unless `blk` is a different block. In a method from
# `define_method`, the owner is the method entry's owner, and the name is
# the name of the definition. An alias keeps that name (`orig`), as a
# def's frame keeps the def's name.
sig [Ptr, Ptr, Word, Ptr, Value] => Value
machine def zr_super(cc, rec, argc, argv, blk)
  recv = Frame.self(rec)
  entry = zr_bmethod_entry(rec)
  if entry != 0
    owner = FrameMeta.owner(MEntry.meta(entry))
    mid = MEntry.orig(entry)
  else
    meta = zr_method_meta_of(rec)
    if meta == 0
      zr_kw_take()
      return zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
    end
    owner = FrameMeta.owner(meta)
    mid = FrameMeta.name(meta)
  end
  k = zr_super_from(rec, recv, owner)
  # The site's cache entry is valid for the node and name that it was
  # filled for, under the method stamp, as for a send. The callee reads
  # the keywords that the site set.
  t = zr_task()
  if cc != 0 && k != QNIL && SuperCache.node(cc) == k && SuperCache.mid(cc) == mid && SuperCache.stamp(cc) == Machine.load64(Machine.static(:mcache_stamp, 8), 0) && Task.refine(t) == QNIL
    return Machine.call(:method, SuperCache.fn(cc), recv, argc, argv, SuperCache.entry(cc), blk, SuperCache.found(cc))
  end
  kw = zr_kw_take()
  e = 0
  refined = false
  if k != QNIL && zr_type(k) == T_MODULE && ClassExt.refined(RClass.ext(k)) != QNIL
    # `super` in a refined method finds the method that the refinement
    # overrides. It searches the refined class's ancestor list with no
    # refinements, because the refinement would otherwise find itself.
    e = zr_search_method(ClassExt.refined(RClass.ext(k)), mid)
    refined = true
  elsif k != QNIL
    e = zr_find_method(RClass.superclass(k), mid)
  end
  # vm_call_super: with no method above, the receiver's method_missing
  # gets the call (MISSING_SUPER).
  if e == 0
    return zr_method_missing(recv, mid, argc, argv, blk, kw, MISS_SUPER)
  end
  if cc != 0 && !refined && Task.refine(t) == QNIL && Machine.load64(Machine.static(:mcache_mode, 8), 0) == 0
    SuperCache.set_node(cc, k)
    SuperCache.set_mid(cc, mid)
    SuperCache.set_stamp(cc, Machine.load64(Machine.static(:mcache_stamp, 8), 0))
    SuperCache.set_entry(cc, e)
    SuperCache.set_found(cc, zr_entry_found(e))
    SuperCache.set_fn(cc, zr_entry_fn(e))
  end
  r = zr_invoke(e, recv, argc, argv, blk, kw)
  # The site activated the refinements for this super only.
  Task.set_refine(t, Machine.value(QNIL))
  r
end

# Returns the ancestor list node where the lookup found the frame's
# method (through its blocks). Returns nil for a frame that the kernel
# pushed.
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

# Returns the method entry of the `define_method` method that the frame
# runs in, or 0.
sig [Ptr] => Ptr
machine def zr_bmethod_entry(rec)
  cref = Frame.cref(rec)
  if cref == QNIL || RCref.eval(cref) == 0
    return 0
  end
  RCref.entry(cref)
end

# Returns the meta of the def that contains the frame, through its
# blocks and evals. Returns 0 in a class body or at the top level.
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

# `defined?(super)`: whether a method is after this frame's owner.
sig [Ptr] => Value
machine def zr_super_defined(rec)
  entry = zr_bmethod_entry(rec)
  if entry != 0
    owner = FrameMeta.owner(MEntry.meta(entry))
    mid = MEntry.orig(entry)
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

# Returns the node after which a `super` in the frame continues. This is
# the method frame's defining node when that node represents `owner` (a
# module included twice has two nodes). Otherwise it is the first node
# of `owner` in the receiver's ancestor list. Returns nil when there is
# none.
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

# A bare `super` in a block. When the block runs as a method from
# `define_method`, CRuby raises for implicit arguments, in all defs.
sig [Ptr] => Value
machine def zr_zsuper_in_block(rec)
  if zr_bmethod_entry(rec) != 0
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."), 125)
  end
  Machine.value(QNIL)
end

# A bare `super` outside a def. In a method from `define_method` it
# raises the implicit-argument error. Elsewhere there is no method.
sig [Ptr] => Value
machine def zr_zsuper_outside(rec)
  r = zr_zsuper_in_block(rec)
  return r if r == QUNDEF
  zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
end

# Calls through the method entry `e`. A compiled def gets the keywords
# flag and pushes its own frame. A builtin runs under a frame that this
# pushes.
sig [Ptr, Value, Word, Ptr, Value, Word] => Value
machine def zr_invoke(e, recv, argc, argv, blk, kw)
  kind = MEntry.kind(e)
  if kw > 1 && kind != KIND_DEF && kind != KIND_BMETHOD
    argc = zr_kw_tab_in(kw, argc, argv)
    kw = 1
  end
  if kind == KIND_DEF
    arity = MEntry.arity(e)
    if arity >= 0
      # For a def with a fixed count, which declares no keywords, the
      # table's values are one Hash argument.
      given = kw > 1 ? argc - Machine.load64(kw, 0) + 1 : argc
      if given != arity
        return zr_wrong_arity_in(given, arity, e, recv)
      end
    end
    Task.set_kw(zr_task(), kw)
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, e, blk, zr_entry_found(e))
  end
  # An accessor has no frame, so its arity error comes from the caller.
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
  if MEntry.kind(e) == KIND_STRUCT_AREF
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    return zr_struct_get(recv, e)
  end
  if MEntry.kind(e) == KIND_STRUCT_ASET
    if argc != 1
      return zr_wrong_arity(argc, 1)
    end
    return zr_struct_set(recv, e, Machine.value(Machine.load64(argv, 0)))
  end
  if MEntry.kind(e) == KIND_FRAMELESS
    Task.set_kw(zr_task(), kw)
    return Machine.call(:builtin, MEntry.fn(e), recv, argc, argv, Machine.value(QNIL), blk)
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
  # A builtin can run Ruby that calls builtins again, with no compiled
  # frame between them. Thus its frame does the stack check of a
  # compiled prologue, before it links the frame.
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
  # The entry gives the name used in the call, which can be an alias. An
  # enumerator that the builtin returns records that name.
  Frame.set_entry(rec, e)
  Frame.set_svars(rec, Machine.value(QNIL))
  Frame.set_defined(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  Task.set_kw(t, kw)
  arity = MEntry.arity(e)
  if arity >= 0 && argc != arity
    r = zr_wrong_arity(argc, arity)
  else
    r = Machine.call(:builtin, MEntry.fn(e), recv, argc, argv, Machine.value(QNIL), blk)
  end
  Task.set_kw(t, 0)
  Task.set_top(t, Frame.prev(rec))
  r
end

# Raises an arity error of a compiled method under that method's frame,
# as CRuby's backtrace shows it.
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
  Frame.set_entry(rec, e)
  Frame.set_svars(rec, Machine.value(QNIL))
  Frame.set_defined(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  r = zr_wrong_arity(given, expected)
  Task.set_top(t, Frame.prev(rec))
  r
end

# Returns the ancestor list node that a method's frame records as its
# definition point. For an alias or a visibility copy, it is the source
# node. Otherwise it is the node where the lookup found the method.
sig [Ptr] => Value
machine def zr_entry_found(e)
  from = MEntry.from(e)
  from != QNIL ? from : Task.found(zr_task())
end

# The kernel's own sends, which have no site and thus no cache entry.
# Compiled Ruby sends through `zr_send_cached` (cache.rb).
sig [Value, Word, Word, Ptr] => Value
machine def zr_send(recv, mid, argc, argv)
  zr_dispatch(0, recv, mid, argc, argv, 0, Machine.value(QNIL))
end

sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_send_blk(recv, mid, argc, argv, blk)
  zr_dispatch(0, recv, mid, argc, argv, 0, blk)
end

# `Hash.ruby2_keywords_hash`: a copy with the flag. The next function
# checks for the flag.
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

# Preemption. A green thread that only computes makes no blocking call,
# so no other thread can run. Every safe point reads the poll word
# (`zr_poll_slot`, next to the task word): a compiled loop's back edge,
# a compiled method's entry, and the kernel's loops through
# `zr_preempt`. The kernel acts at a safe point only when the word is
# set. The timer thread sets it every 100 ms after a second thread starts
# (`zr_os_poll_start`). A caught POSIX signal and a collection that
# queued a finalizer also set it. Under wasm there is no timer thread,
# so a count is the clock: compiled back edges decrement it, and the
# kernel's loops decrement it here. Thread sets the receiver and message
# when a second thread starts, so a one-thread program never yields to
# the scheduler.
PREEMPT_TICKS = 20_000

sig [Value, Value] => Value
machine def zr_preempt_arm(receiver, message)
  Machine.store64(Machine.static(:preempt_mid, 8), 0, zr_sym2id(message))
  Machine.store64(Machine.static(:preempt_to, 8), 0, Machine.word(receiver))
  zr_os_poll_start()
  Machine.value(QNIL)
end

# Requests action at the next safe point, for a POSIX signal, a
# finalizer, or the timer.
sig [] => Void
machine def zr_poll_set
  Machine.store64(zr_poll_slot(), 0, 1)
end

# Whether a second thread started. Until then, each task is alone, and
# IO does not need to call the scheduler before a system call.
sig [] => Value
machine def zr_threaded
  zr_bool(Machine.load64(Machine.static(:preempt_to, 8), 0) != 0)
end

sig [] => Value
machine def zr_preempt
  count = Machine.static(:preempt_count, 8)
  n = Machine.load64(count, 0) - 1
  Machine.store64(count, 0, n)
  if n > 0 && Machine.load64(zr_poll_slot(), 0) == 0
    return Machine.value(QNIL)
  end
  zr_preempt_expired()
end

# Runs a requested safe point. It resets the poll word and the count,
# runs the handlers of POSIX signals that arrived, and runs the
# finalizers that a collection queued. Then, if a second thread set up
# preemption, it yields to the scheduler.
sig [] => Value
machine def zr_preempt_expired
  Machine.store64(zr_poll_slot(), 0, 0)
  Machine.store64(Machine.static(:preempt_count, 8), 0, PREEMPT_TICKS)
  if zr_trap_check() == QUNDEF
    return Machine.value(QUNDEF)
  end
  if WeakList.len(zr_finalizer_queue()) > 0 && zr_finalizers_run() == QUNDEF
    return Machine.value(QUNDEF)
  end
  mid = Machine.load64(Machine.static(:preempt_mid, 8), 0)
  if mid == 0
    return Machine.value(QNIL)
  end
  zr_preempt_send(mid)
end

# Yields to the scheduler through the receiver that Thread set. It never
# does this while this task is already in one of those sends, because
# the scheduler runs its own compiled Ruby, with back edges.
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

# Whether `v` responds to `mid`, as rb_check_funcall decides before a
# conversion calls it. If the program defines respond_to? and it returns
# false, the result is false. If a method exists, the result is true.
# Otherwise, if the program defines respond_to_missing? and it returns
# true, the result is true and method_missing handles the call. Returns
# QUNDEF when a hook raised.
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

# rb_check_funcall with no arguments: the result of `name`, or nil when
# `v` does not respond to it. As in ruby, a method_missing of the
# program answers when respond_to_missing? and respond_to? are the
# core's, and a NoMethodError from it means that `v` does not respond
# (check_funcall_missing). Works on a BasicObject, which has neither
# respond_to? nor is_a?. Returns QUNDEF when a call raised.
sig [Value, Value] => Value
machine def zr_check_call(v, name)
  mid = zr_sym2id(name)
  responds = zr_check_funcall(v, mid)
  return responds if responds == QUNDEF
  if responds == QTRUE
    return zr_send(v, mid, 0, 0)
  end
  klass = zr_class_of(v)
  missing = zr_find_method(klass, Machine.id(:method_missing))
  if missing == 0 || MEntry.core(missing) != 0
    return Machine.value(QNIL)
  end
  answers = zr_find_method(klass, Machine.id(:respond_to_missing?))
  asks = zr_find_method(klass, Machine.id(:respond_to?))
  if (answers != 0 && MEntry.core(answers) == 0) || (asks != 0 && MEntry.core(asks) == 0)
    return Machine.value(QNIL)
  end
  r = zr_send(v, mid, 0, 0)
  if r == QUNDEF
    exc = zr_rescuable()
    if exc != QUNDEF && zr_is_a(exc, zr_global(G_NO_METHOD_ERROR))
      Task.set_pending(zr_task(), Machine.value(QNIL))
      return Machine.value(QNIL)
    end
  end
  r
end
