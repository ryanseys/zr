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
#   visibility the caller's self cannot change.
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
# frame as a lookup would. `ivar` is the guess an accessor entry reads
# and writes through.
Machine.struct :CallCache, klass: Value, stamp: Word, entry: Ptr, found: Value, ivar: IvarCache
Machine.struct :ConstCache, key: Value, stamp: Word, value: Value

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
  if Task.refine(Machine.ptr(Machine.load64(Machine.static(:current_task, 8), 0))) != QNIL
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
sig [Ptr, Value, Ptr, Word] => Void
machine def zr_call_cache_fill(cc, klass, e, mode)
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
  CallCache.set_klass(cc, klass)
  CallCache.set_stamp(cc, Machine.load64(Machine.static(:mcache_stamp, 8), 0))
  CallCache.set_entry(cc, e)
  CallCache.set_found(cc, Task.found(t))
end

# A send through the site's cell. A hit calls a compiled def straight
# away and reads or writes an accessor's ivar through the cell's guess;
# any other entry goes through `zr_invoke`, as a dispatch would send it.
# A miss is a dispatch, which fills the cell.
sig [Ptr, Value, Word, Word, Ptr, Value, Word] => Value
machine def zr_send_cached(cc, recv, mid, argc, argv, blk, mode)
  e = zr_call_cache_hit(cc, recv, mid)
  if e == 0
    return zr_dispatch(cc, recv, mid, argc, argv, mode, blk)
  end
  t = Machine.ptr(Machine.load64(Machine.static(:current_task, 8), 0))
  Task.set_found(t, CallCache.found(cc))
  kind = MEntry.kind(e)
  if kind == KIND_DEF && (MEntry.arity(e) < 0 || MEntry.arity(e) == argc)
    # `zr_invoke`'s steps, but for the keywords flag: a dispatch takes
    # it and hands it straight back, so it stays as it is.
    Task.set_mid(t, MEntry.mid(e))
    if MEntry.from(e) != QNIL
      Task.set_found(t, MEntry.from(e))
    end
    return Machine.call(:method, MEntry.fn(e), recv, argc, argv, MEntry.cref(e), blk)
  end
  if kind == KIND_ATTR_READER && argc == 0
    Task.set_kw(t, 0)
    return zr_ivar_get_cached(recv, Machine.word(MEntry.fn(e)), CallCache.ivar(cc))
  end
  if kind == KIND_ATTR_WRITER && argc == 1
    Task.set_kw(t, 0)
    return zr_ivar_set_cached(recv, Machine.word(MEntry.fn(e)), Machine.value(Machine.load64(argv, 0)), CallCache.ivar(cc))
  end
  zr_invoke(e, recv, argc, argv, blk, zr_kw_take())
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
      zr_call_cache_fill(cc, klass, e, mode)
    end
  end
  if e == 0 || MEntry.fn(e) != Machine.addr(:zr_class_new_instance) || MEntry.vis(e) != VIS_PUBLIC
    return zr_send_cached(cc, recv, Machine.id(:new), argc, argv, Machine.value(QNIL), mode)
  end
  o = zr_class_new_object(recv)
  return o if o == QUNDEF
  r = zr_send_cached(cc + CallCache.size, o, Machine.id(:initialize), argc, argv, Machine.value(QNIL), 0)
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
    zr_ivtab_set(t, id, v)
  else
    IvEntry.set_value(e, v)
  end
  v
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
