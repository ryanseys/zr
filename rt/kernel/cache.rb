# Call-site caches. A site in compiled Ruby that sends a message, reads
# a constant, or reads or writes an instance variable owns a cell in
# `.bss`, zero at the start, which keeps the answer it last got there.
# The kernel both fills and trusts every cell, so what makes an answer
# stale is written down here and nowhere else.
#
# A cell answers only from what it was keyed on:
#
# - A send's cell keys on the receiver's class and the method stamp,
#   which every change to a method table or a chain moves
#   (`zr_methods_changed`). It is filled only when nothing else decided
#   the answer: no refinement in use, no box shadow of the class, and a
#   visibility the caller's self cannot change. The site tests the
#   class and the stamp itself and calls the cell's `fn` straight
#   (`Zr::Function::Sends#cached_send`); its stamp is the site stamp,
#   which follows the method stamp while the cells are trusted and is
#   -1 while they are off or verified, so that every send then comes
#   through `zr_send_cached`.
# - A constant's cell keys on the cref, or on the scope of `A::B`, and
#   on the constant stamp, which moves on every constant write, removal
#   and flag, on every chain change, and on every cref the collector
#   frees (its address can come back as another cref). It never holds
#   an autoload, a deprecated constant, or a read made inside a box.
# - An instance variable's cell holds only a guess: the row the name sat
#   in last time. Every use checks the guess against the row's name, so
#   a cell is never stale, only wrong, and a wrong guess costs one scan.
#
# `ZR_MCACHE=0` fills no cell, and `ZR_MCACHE=verify` checks every hit
# of a send's or a constant's cell against a fresh lookup.
Machine.struct :IvarCache, index: Word
# `found` is the chain node the entry sat on, which a call hands the
# frame as a lookup would. `fn` is what a hit calls, with the method
# signature whatever the entry's kind (`zr_entry_fn`). A site owns
# CALL_WAYS cells in a row: the first it tests itself, the rest the
# kernel tests when the first misses, so a site whose receivers come
# from a few classes hits on each.
# `shape` says what a site may do in place of the call: an accessor's
# ivar the site reads or writes itself (`Zr::Function::Sends
# #accessor_in_place`), one of the core's type questions it answers
# itself (`#in_place`), and SHAPE_NONE every other kind, which is
# what a cell holds until a fill says otherwise.
Machine.struct :CallCache, klass: Value, stamp: Word, entry: Ptr, found: Value, fn: Ptr, shape: Word
CALL_WAYS = 4
SHAPE_NONE = 0
SHAPE_READER = 1
SHAPE_WRITER = 2
SHAPE_IS_A = 3
SHAPE_INSTANCE_OF = 4
SHAPE_NIL_P = 5
SHAPE_FROZEN_P = 6
SHAPE_ARY_LENGTH = 7
SHAPE_MOD_EQQ = 8
Machine.struct :ConstCache, key: Value, stamp: Word, value: Value
# A `super` site's cell: the chain node the method runs from and the
# name, which together decide the next method, and what the lookup
# found for them under the method stamp (rt/kernel/send.rb, zr_super).
Machine.struct :SuperCache, node: Value, mid: Word, stamp: Word, entry: Ptr, found: Value, fn: Ptr

# Any change a constant lookup could see.
sig [] => Void
machine def zr_consts_changed
  s = Machine.static(:const_stamp, 8)
  Machine.store64(s, 0, Machine.load64(s, 0) + 1)
end

# The entry `cc` holds for a send of `mid` to `recv`, or 0 when it
# holds none that stands. A heap receiver's class is its header's, as
# `zr_class_of` reads it; a special constant's is asked for. The task is
# read from its static word: every send comes through here.
sig [Ptr, Value, Word] => Ptr
machine def zr_call_cache_hit(cc, recv, mid)
  w = Machine.word(recv)
  if (w & 7) == 0 && w != QFALSE && w != QNIL
    klass = RBasic.klass(recv)
  else
    klass = zr_class_of(recv)
  end
  if klass != CallCache.klass(cc) || CallCache.stamp(cc) != Machine.load64(Machine.static(:mcache_stamp, 8), 0)
    return 0
  end
  if Task.refine(Machine.ptr(Machine.load64(Machine.static(:current_task, 16), 0))) != QNIL
    return 0
  end
  e = CallCache.entry(cc)
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY && e != zr_search_method(klass, mid)
    zr_bug(Machine.bytes("a call cache answered what the chain does not\n"), 46)
  end
  e
end

# The answer `zr_dispatch` just found for `klass`, into the cell when
# the class and the stamp alone decided it.
sig [Ptr, Value, Ptr, Word, Word] => Void
machine def zr_call_cache_fill(cc, klass, e, mid, mode)
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_OFF
    return
  end
  t = zr_task()
  if Task.refine(t) != QNIL || ClassExt.boxed(RClass.ext(klass)) != QNIL
    return
  end
  # A private or protected method refuses an explicit receiver by who
  # calls, not by the class.
  if (mode & SEND_MODE) >= 2 && MEntry.vis(e) != VIS_PUBLIC
    return
  end
  # A core send's own entry is not the chain's when the program has
  # redefined the method: the verifier, which asks the chain, leaves
  # such a cell empty rather than read it as wrong.
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY && (mode & SEND_CORE) != 0 && e != zr_search_method(klass, mid)
    return
  end
  CallCache.set_klass(cc, klass)
  CallCache.set_stamp(cc, Machine.load64(Machine.static(:mcache_stamp, 8), 0))
  CallCache.set_entry(cc, e)
  CallCache.set_found(cc, zr_entry_found(e))
  CallCache.set_fn(cc, zr_entry_fn(e))
  CallCache.set_shape(cc, zr_entry_shape(e))
end

# What a site may do in place of the call to `e`: an accessor's whole
# body, one guessed row read or written, which is what
# `zr_attr_reader_fn` and `zr_attr_writer_fn` do and nothing more;
# or one of the core's type questions, named by the builtin that
# answers it. The builtin is the test, not the name: a class that
# defines its own `is_a?` finds another entry, and its cell holds
# SHAPE_NONE.
sig [Ptr] => Word
machine def zr_entry_shape(e)
  kind = MEntry.kind(e)
  if kind == KIND_ATTR_READER
    return SHAPE_READER
  end
  if kind == KIND_ATTR_WRITER
    return SHAPE_WRITER
  end
  if kind != KIND_BUILTIN
    return SHAPE_NONE
  end
  fn = MEntry.fn(e)
  if fn == Machine.addr(:zr_obj_is_a)
    return SHAPE_IS_A
  end
  if fn == Machine.addr(:zr_obj_instance_of)
    return SHAPE_INSTANCE_OF
  end
  if fn == Machine.addr(:zr_obj_nil_p)
    return SHAPE_NIL_P
  end
  if fn == Machine.addr(:zr_obj_frozen_p)
    return SHAPE_FROZEN_P
  end
  if fn == Machine.addr(:zr_ary_length)
    return SHAPE_ARY_LENGTH
  end
  if fn == Machine.addr(:zr_mod_eqq)
    return SHAPE_MOD_EQQ
  end
  SHAPE_NONE
end

# `is_a?` at a site whose cell holds Kernel#is_a?, for a receiver of
# class `klass`: where `mod` is a class and both chains are built, a
# class's rank settles it in two loads, as `zr_class_inherits` does.
# Anything else answers nil and the site calls the builtin, which
# walks a module's chain, reads a box's view, and raises for what is
# neither a class nor a module. A box shadow stands for the shared
# class (`zr_is_a`), so a target that has one is the builtin's too.
#
# One test a line, each returning: an `||` chain is lowered as the
# booleans it joins, where these want a branch each.
sig [Value, Value] => Value
machine def zr_is_a_fast(klass, mod)
  w = Machine.word(mod)
  if (w & 7) != 0
    return Machine.value(QNIL)
  end
  if w <= QNIL
    return Machine.value(QNIL)
  end
  if (RBasic.flags(mod) & T_MASK) != T_CLASS
    return Machine.value(QNIL)
  end
  if (RBasic.flags(klass) & T_MASK) != T_CLASS
    return Machine.value(QNIL)
  end
  ext = RClass.ext(klass)
  target = RClass.ext(mod)
  if ClassExt.supers(ext) == 0
    return Machine.value(QNIL)
  end
  if ClassExt.supers(target) == 0
    return Machine.value(QNIL)
  end
  if ClassExt.boxed(ext) != QNIL
    return Machine.value(QNIL)
  end
  if ClassExt.shadow(target) != QNIL
    return Machine.value(QNIL)
  end
  r = ClassExt.rank(target)
  if r > ClassExt.rank(ext)
    return Machine.value(QFALSE)
  end
  zr_bool(Machine.value(Machine.load64(ClassExt.supers(ext) + ((r - 1) * 8), 0)) == mod)
end

# `mod === obj` at a site whose cell holds Module#===, which is what
# `case obj when mod` asks: `obj.is_a?(mod)` as the builtin answers
# it (`zr_mod_eqq`), never through a method `obj` defines. A cell's
# class is its header's; any other value's is `zr_class_of`'s.
sig [Value, Value] => Value
machine def zr_mod_eqq_fast(mod, obj)
  w = Machine.word(obj)
  if (w & 7) == 0 && w > QUNDEF
    return zr_is_a_fast(RBasic.klass(obj), mod)
  end
  zr_is_a_fast(zr_class_of(obj), mod)
end

# `instance_of?` at a site whose cell holds Kernel#instance_of?, for
# a receiver of class `klass`: whether its real class, past a
# singleton class and the proxies of what it extends, is `c`
# (`zr_real_class`). Nil where `c` is neither a class nor a module,
# which the builtin raises for.
sig [Value, Value] => Value
machine def zr_instance_of_fast(klass, c)
  if !zr_module_p(c)
    return Machine.value(QNIL)
  end
  k = klass
  while zr_singleton_p(k) || zr_type(k) == T_ICLASS
    k = RClass.superclass(k)
  end
  zr_bool(k == c)
end

# What a hit on entry `e` calls with the method signature: a compiled
# def itself, an accessor's own function, and for any other kind the
# dispatch's steps, which push the frame and check the arity.
sig [Ptr] => Ptr
machine def zr_entry_fn(e)
  kind = MEntry.kind(e)
  if kind == KIND_DEF
    return MEntry.fn(e)
  end
  if kind == KIND_BUILTIN
    return Machine.addr(:zr_builtin_fn)
  end
  if kind == KIND_ATTR_READER
    return Machine.addr(:zr_attr_reader_fn)
  end
  if kind == KIND_ATTR_WRITER
    return Machine.addr(:zr_attr_writer_fn)
  end
  if kind == KIND_BMETHOD
    return Machine.addr(:zr_bmethod_fn)
  end
  if kind == KIND_STRUCT_AREF
    return Machine.addr(:zr_struct_aref_fn)
  end
  if kind == KIND_STRUCT_ASET
    return Machine.addr(:zr_struct_aset_fn)
  end
  Machine.addr(:zr_invoke_fn)
end

# A hit on an entry that is not a compiled def: what a dispatch would
# do with it. A keywords Hash the site flagged is taken here, as the
# dispatch takes it.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_invoke_fn(recv, argc, argv, e, blk, found)
  Task.set_found(zr_task(), found)
  zr_invoke(e, recv, argc, argv, blk, zr_kw_take())
end

# A hit on a builtin entry: the dispatch's steps for a builtin alone
# (rt/kernel/send.rb, zr_invoke), with no kind to test. A keyword
# table becomes one Hash argument first; the frame pushed here names
# the builtin in a backtrace and takes the stack check a compiled
# prologue makes; the arity is checked under it.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_builtin_fn(recv, argc, argv, e, blk, found)
  t = zr_task()
  Task.set_found(t, found)
  kw = Task.kw(t)
  if kw > 1
    argc = zr_kw_tab_in(kw, argc, argv)
    kw = 1
  end
  rec = Machine.slot(Frame.size)
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

# An accessor has no frame, so its arity error is the caller's. The
# ivar's id is the entry's `fn`, and the row guess is the entry's own.
#
# The guessed row is read here rather than asked of
# `zr_ivar_get_cached`, which asks `zr_ivar_row_guessed` for it. A site
# that reads `@name` of its own tests the guess inline (the lowering's
# `guessed_ivar_row`); a site that calls a reader pays a call for the
# same three loads, and two more under it. Sampling bm_attr_accessor
# put 261 of 389 samples in these three frames, 131 of them in
# `zr_ivar_row_guessed` alone. So the test stands here, where the
# entry already is, and only a receiver the guess does not settle --
# a class, a module, a special constant, a ractor's object, a wrong
# guess -- goes on to the kernel's own read, which sets the guess.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_attr_reader_fn(recv, argc, argv, e, blk, found)
  if argc != 0
    return zr_wrong_arity(argc, 0)
  end
  t = zr_task()
  Task.set_kw(t, 0)
  id = Machine.word(MEntry.fn(e))
  ic = MEntry.ivar(e)
  w = Machine.word(recv)
  if (w & 7) == 0 && w > QNIL && (RBasic.flags(recv) & T_MASK) == T_OBJECT && Task.ractor(t) == 0
    row = zr_ivar_guess_row(RObject.iv(recv), id, ic)
    if row != 0
      v = IvEntry.value(row)
      return v == QUNDEF ? Machine.value(QNIL) : v
    end
  end
  zr_ivar_get_cached(recv, id, ic)
end

# The frozen bit rides with the type here, as it does in
# `zr_ivar_set_cached`: a frozen receiver is not a plain unfrozen
# object, so it takes the kernel's write, which raises at the caller's
# line.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_attr_writer_fn(recv, argc, argv, e, blk, found)
  if argc != 1
    return zr_wrong_arity(argc, 1)
  end
  t = zr_task()
  Task.set_kw(t, 0)
  id = Machine.word(MEntry.fn(e))
  ic = MEntry.ivar(e)
  v = Machine.value(Machine.load64(argv, 0))
  w = Machine.word(recv)
  if (w & 7) == 0 && w > QNIL && (RBasic.flags(recv) & (T_MASK | FL_FREEZE)) == T_OBJECT && Task.ractor(t) == 0
    row = zr_ivar_guess_row(RObject.iv(recv), id, ic)
    if row != 0
      IvEntry.set_value(row, v)
      zr_write_barrier(recv, v)
      return v
    end
  end
  zr_ivar_set_cached(recv, id, v, ic)
end

# The row of table `t` the cell `ic` guesses, when the table is long
# enough and that row holds `id`; else 0. What `zr_ivar_row_guessed`
# does once it knows the table, and small enough that an accessor
# carries a copy rather than a call.
sig [Ptr, Word, Ptr] => Ptr
machine def zr_ivar_guess_row(t, id, ic)
  i = IvarCache.index(ic)
  if i >= IvTab.len(t)
    return 0
  end
  e = IvTab.rows(t) + (i * IvEntry.size)
  IvEntry.id(e) == id ? e : 0
end

# A send through the site's cell, for a site whose own test of the cell
# did not hit (a special constant, a stale cell, a refinement in use,
# the cells off or verified). A hit here calls the cell's `fn`; a miss
# is a dispatch, which fills the cell.
sig [Ptr, Value, Word, Word, Ptr, Value, Word] => Value
machine def zr_send_cached(cc, recv, mid, argc, argv, blk, mode)
  if Task.refine(zr_task()) == QNIL
    # The class and the stamp once, then each way in place. The site
    # tested the first way itself for a cell or a fixnum receiver; any
    # other receiver reached it untested, and under ZR_MCACHE=verify
    # no site's own test hits, so the first way is tested here and
    # every hit is held to the chain.
    w = Machine.word(recv)
    verify = Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
    if (w & 7) == 0 && w > QUNDEF
      klass = RBasic.klass(recv)
      i = verify ? 0 : 1
    elsif (w & 1) != 0
      klass = zr_global(G_INTEGER)
      i = verify ? 0 : 1
    else
      klass = zr_class_of(recv)
      i = 0
    end
    stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
    while i < CALL_WAYS
      way = cc + (i * CallCache.size)
      if CallCache.klass(way) == klass && CallCache.stamp(way) == stamp
        e = CallCache.entry(way)
        if verify && e != zr_search_method(klass, mid)
          zr_bug(Machine.bytes("a call cache answered what the chain does not\n"), 46)
        end
        return Machine.call(:method, CallCache.fn(way), recv, argc, argv, e, blk, CallCache.found(way))
      end
      i += 1
    end
  end
  zr_dispatch(zr_call_cache_slot(cc), recv, mid, argc, argv, mode, blk)
end

# The cell a dispatch fills: the first that is empty or stale, else
# the last, so the class the site tests itself keeps the first.
sig [Ptr] => Ptr
machine def zr_call_cache_slot(cc)
  i = 0
  while i < CALL_WAYS - 1
    way = cc + (i * CallCache.size)
    if CallCache.klass(way) == 0 || CallCache.stamp(way) != Machine.load64(Machine.static(:mcache_stamp, 8), 0)
      return way
    end
    i += 1
  end
  cc + ((CALL_WAYS - 1) * CallCache.size)
end

# A `new` call with no block, CRuby's `opt_new`, with a cell for each of
# its two lookups: `new` on the receiver's class, then `initialize` on
# the object it makes. The builtin `Class#new` reached as a public
# method runs with no frame of its own, so a backtrace goes from
# `initialize` straight to the caller; any other `new` is a send through
# the cell the lookup filled.
sig [Ptr, Value, Word, Ptr, Word] => Value
machine def zr_new_cached(cc, recv, argc, argv, mode)
  e = zr_call_cache_hit(cc, recv, Machine.id(:new))
  if e == 0
    klass = zr_box_view(zr_class_of(recv))
    e = zr_find_method(klass, Machine.id(:new))
    if e != 0
      zr_call_cache_fill(cc, klass, e, Machine.id(:new), mode)
    end
  end
  if e == 0 || MEntry.fn(e) != Machine.addr(:zr_class_new_instance) || MEntry.vis(e) != VIS_PUBLIC
    return zr_send_cached(cc, recv, Machine.id(:new), argc, argv, Machine.value(QNIL), mode)
  end
  o = zr_class_new_object(recv)
  return o if o == QUNDEF
  r = zr_send_cached(cc + (CallCache.size * CALL_WAYS), o, Machine.id(:initialize), argc, argv, Machine.value(QNIL), 0)
  return r if r == QUNDEF
  o
end

# Whether row `e`'s value may stand in a cell: set (not an autoload
# still to run), not deprecated (each read warns), and read outside a
# box (a box sees rows and classes of its own).
sig [Ptr] => Bool
machine def zr_const_cacheable(e)
  CEntry.value(e) != QUNDEF && CEntry.deprecated(e) == 0 && zr_box_current() == QNIL
end

# `stamp` is the one read before the lookup: whatever the lookup set
# off leaves the cell stale at once.
sig [Ptr, Value, Word, Value] => Void
machine def zr_const_cache_fill(cc, key, stamp, v)
  if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_OFF
    return
  end
  ConstCache.set_key(cc, key)
  ConstCache.set_stamp(cc, stamp)
  ConstCache.set_value(cc, v)
end

# `ZR_MCACHE=verify`: the row a fresh lookup finds holds what the cell
# answered.
sig [Ptr, Ptr] => Void
machine def zr_const_cache_verify(cc, e)
  if e == 0 || !zr_const_cacheable(e) || CEntry.value(e) != ConstCache.value(cc)
    zr_bug(Machine.bytes("a constant cache answered what the lookup does not\n"), 51)
  end
end

# A bare constant under `cref` at a site: `zr_const_get`'s answer.
sig [Ptr, Value, Word] => Value
machine def zr_const_get_cached(cc, cref, id)
  stamp = Machine.load64(Machine.static(:const_stamp, 8), 0)
  if ConstCache.key(cc) == cref && ConstCache.stamp(cc) == stamp
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
      zr_const_cache_verify(cc, zr_const_row_under(cref, id))
    end
    return ConstCache.value(cc)
  end
  e = zr_const_row_under(cref, id)
  if e != 0 && zr_const_cacheable(e)
    zr_const_cache_fill(cc, cref, stamp, CEntry.value(e))
    return CEntry.value(e)
  end
  zr_const_get(cref, id)
end

# `scope::Name` at a site: `zr_const_get_at`'s answer. A private
# constant raises here each time, so its row stays out of the cell.
sig [Ptr, Value, Word] => Value
machine def zr_const_get_at_cached(cc, scope, id)
  stamp = Machine.load64(Machine.static(:const_stamp, 8), 0)
  if ConstCache.key(cc) == scope && ConstCache.stamp(cc) == stamp
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
      zr_const_cache_verify(cc, zr_const_row_in(scope, id, scope != zr_global(G_OBJECT)))
    end
    return ConstCache.value(cc)
  end
  if !zr_special_p(scope) && (zr_type(scope) == T_CLASS || zr_type(scope) == T_MODULE)
    e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
    if e != 0 && CEntry.private(e) == 0 && zr_const_cacheable(e)
      zr_const_cache_fill(cc, scope, stamp, CEntry.value(e))
      return CEntry.value(e)
    end
  end
  zr_const_get_at(scope, id)
end

# `@name` at a site whose cell `ic` guesses its row: `zr_ivar_get`'s
# answer.
sig [Value, Word, Ptr] => Value
machine def zr_ivar_get_cached(obj, id, ic)
  e = zr_ivar_row_guessed(obj, id, ic)
  if e != 0
    v = IvEntry.value(e)
    return v == QUNDEF ? Machine.value(QNIL) : v
  end
  g = zr_ractor_guard(obj)
  if g == QUNDEF
    return g
  end
  t = zr_ivtab(obj)
  if t == 0
    return Machine.value(QNIL)
  end
  e = zr_ivtab_guess(t, id, ic)
  if e == 0 || IvEntry.value(e) == QUNDEF
    return Machine.value(QNIL)
  end
  IvEntry.value(e)
end

# `@name = v` at a site whose cell `ic` guesses its row: `zr_ivar_set`'s
# answer.
sig [Value, Word, Value, Ptr] => Value
machine def zr_ivar_set_cached(obj, id, v, ic)
  e = zr_ivar_row_guessed(obj, id, ic)
  if e != 0 && (RBasic.flags(obj) & FL_FREEZE) == 0
    IvEntry.set_value(e, v)
    zr_write_barrier(obj, v)
    return v
  end
  # A plain object outside a ractor, not frozen, whose guess is the row
  # past its last: the first assignment in an `initialize`, whose row
  # goes there when none holds `id` yet, with no more of the kernel
  # between.
  if !zr_special_p(obj) && (RBasic.flags(obj) & (T_MASK | FL_FREEZE)) == T_OBJECT && Task.ractor(zr_task()) == 0
    t = RObject.iv(obj)
    if IvarCache.index(ic) == IvTab.len(t) && zr_ivtab_row(t, id) == 0
      zr_ivtab_append(t, id, v, obj)
      zr_write_barrier(obj, v)
      return v
    end
  end
  g = zr_ractor_guard(obj)
  if g == QUNDEF
    return g
  end
  if zr_modify_frozen_p(obj)
    return zr_frozen_error(obj)
  end
  t = zr_ivtab_for_write(obj)
  e = zr_ivtab_guess(t, id, ic)
  if e == 0
    # A new row goes last, where the next guess finds it.
    IvarCache.set_index(ic, IvTab.len(t))
    zr_ivtab_set_in(t, id, v, zr_ivtab_owner(obj))
  else
    IvEntry.set_value(e, v)
  end
  zr_write_barrier(obj, v)
  v
end

# The row of an object's, class's or module's own table the cell
# guesses, when it holds `id` and the read is outside a ractor (a
# ractor's isolation rule is `zr_ractor_guard`'s); else 0. What a site
# tests inline before it calls here (the lowering's
# `guessed_ivar_row`); an accessor's entry comes straight here.
sig [Value, Word, Ptr] => Ptr
machine def zr_ivar_row_guessed(obj, id, ic)
  if zr_special_p(obj) || Task.ractor(zr_task()) != 0
    return 0
  end
  kind = RBasic.flags(obj) & T_MASK
  if kind == T_OBJECT
    t = RObject.iv(obj)
  elsif kind == T_CLASS || kind == T_MODULE
    t = ClassExt.iv(RClass.ext(obj))
  else
    return 0
  end
  zr_ivar_guess_row(t, id, ic)
end

# The row for `id` in the table `t`, or 0: the guessed one when it holds
# `id`, else the one a scan finds, which becomes the guess.
sig [Ptr, Word, Ptr] => Ptr
machine def zr_ivtab_guess(t, id, ic)
  i = IvarCache.index(ic)
  if i < IvTab.len(t)
    e = IvTab.rows(t) + (i * IvEntry.size)
    if IvEntry.id(e) == id
      return e
    end
  end
  e = zr_ivtab_row(t, id)
  if e != 0
    IvarCache.set_index(ic, (Machine.word(e) - Machine.word(IvTab.rows(t))) / IvEntry.size)
  end
  e
end
