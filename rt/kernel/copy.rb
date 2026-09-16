# `dup` and `clone`: a fresh cell with the same contents, its own
# copies of what the cell owns outside the arena, then
# `initialize_copy`. A clone keeps the frozen bit and the singleton
# class; a dup keeps neither.

# The rows of one ivar table copied into another, fresh, table; the
# object id and the mark a core class puts on a cell it has built
# stay with the original.
sig [Ptr, Ptr] => Void
machine def zr_ivtab_copy(to, from)
  IvTab.set_len(to, 0)
  i = 0
  while i < IvTab.len(from)
    e = IvTab.rows(from) + (i * IvEntry.size)
    if IvEntry.id(e) != Machine.id(:__object_id__) && IvEntry.id(e) != Machine.id(:__built__)
      zr_ivtab_set(to, IvEntry.id(e), IvEntry.value(e))
    end
    i += 1
  end
end

# What the copy owns. A String, an Array or a Hash starts empty, as
# CRuby's allocator leaves one: its own `initialize_copy` is what fills
# it, so a subclass that answers that without `super` copies nothing, as
# it does in ruby.
sig [Value, Value] => Value
machine def zr_copy_payload(copy, orig)
  t = zr_type(orig)
  if t == T_OBJECT
    # The cell's bytes came over, rows pointer and all.
    zr_obj_ivtab_init(copy)
    zr_ivtab_copy(RObject.iv(copy), RObject.iv(orig))
  elsif t == T_STRING
    zr_str_buf_new(copy, 0)
    Machine.store8(RString.ptr(copy), 0, Machine.i8(0))
    RString.set_len(copy, 0)
  elsif t == T_ARRAY
    buf = zr_xmalloc(4 * 8)
    RArray.set_ptr(copy, buf)
    RArray.set_base(copy, buf)
    RArray.set_len(copy, 0)
    RArray.set_capa(copy, 4)
  elsif t == T_HASH
    RHash.set_entries(copy, 0)
    RHash.set_len(copy, 0)
    RHash.set_live(copy, 0)
    RHash.set_cap(copy, 0)
    RHash.set_default(copy, Machine.value(QNIL))
    RHash.set_default_proc(copy, Machine.value(QNIL))
    RHash.set_bins(copy, 0)
    RHash.set_nbins(copy, 0)
    RHash.set_iter(copy, 0)
    RHash.set_gen(copy, 0)
  elsif t == T_EXCEPTION
    if RException.rows(orig) != 0
      rows = zr_xmalloc(RException.nrows(orig) * BtRow.size)
      zr_memcpy(rows, RException.rows(orig), RException.nrows(orig) * BtRow.size)
      RException.set_rows(copy, rows)
    end
  elsif t == T_FIBER
    # CRuby copies a Fiber's fields and not its machine stack, so the copy
    # is a fiber that was never made: no context, no stack, no task of
    # its own, and it refuses to run.
    RFiber.set_task(copy, 0)
    RFiber.set_ctx(copy, 0)
    RFiber.set_stack(copy, 0)
    RFiber.set_kroots(copy, 0)
    RFiber.set_blk(copy, Machine.value(QNIL))
    RFiber.set_status(copy, FIBER_CREATED)
    RFiber.set_prev(copy, Machine.value(QNIL))
    RFiber.set_resuming(copy, Machine.value(QNIL))
    RFiber.set_value(copy, Machine.value(QNIL))
    RFiber.set_yielding(copy, 0)
    RFiber.set_transferred(copy, 0)
  elsif t == T_REGEXP
    RRegexp.set_source(copy, Machine.value(QNIL))
    RRegexp.set_text(copy, Machine.value(QNIL))
    RRegexp.set_names(copy, Machine.value(QNIL))
    RRegexp.set_options(copy, 0)
    RRegexp.set_reg(copy, 0)
    RRegexp.set_alt(copy, 0)
  elsif t != T_PROC && t != T_METHOD
    # The cell already holds the original's words; clear them, or the
    # collector frees what the original still owns when the copy dies.
    memset(Machine.ptr(copy) + RBasic.size, Machine.i32(0), CELL - RBasic.size)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't copy this kind of object"), 30)
  end
  if (RBasic.flags(orig) & FL_EXIVAR) != 0
    zr_ivtab_copy(zr_exivar_tab_for_write(copy), zr_exivar_tab(orig))
  end
  copy
end

# The cell copied, the payload its own, the class the real one; the
# frozen and singleton facts are the caller's to keep or drop.
sig [Value] => Value
machine def zr_copy_cell(orig)
  copy = zr_alloc(zr_type(orig), zr_real_class(orig))
  zr_memcpy(Machine.ptr(copy) + RBasic.size, Machine.ptr(orig) + RBasic.size, CELL - RBasic.size)
  zr_copy_payload(copy, orig)
end

# A copy starts as `allocate` would make one, so a class with no
# allocator has no copies: a Thread, an Encoding. A Proc, a Method and a
# Binding copy as their own kinds do.
sig [Value] => Value
machine def zr_copy_allocatable(recv)
  klass = zr_real_class(recv)
  t = zr_type(recv)
  if t != T_PROC && t != T_METHOD && zr_alloc_undefined_p(zr_alloc_kind(klass))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("allocator undefined for "), 24)
    zr_buf_class(b, klass)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.value(QNIL)
end

# `Array#initialize_copy`, which is what fills a `dup` or a `clone`: the
# other's elements in place of the receiver's, as `replace` puts them.
# Anything but an Array goes through `replace` itself, which converts.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_initialize_copy(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_ARRAY
    return zr_send(recv, Machine.id(:replace), 1, argv)
  end
  if other == recv
    return zr_frozen_p(recv) ? zr_frozen_error(recv) : recv
  end
  r = zr_ary_splice(recv, zr_fix(0), zr_fix(RArray.len(recv)), other)
  return r if r == QUNDEF
  recv
end

# `String#initialize_copy`: the other's bytes and encoding.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_initialize_copy(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_STRING
    return zr_send(recv, Machine.id(:replace), 1, argv)
  end
  r = zr_str_replace(recv, other)
  return r if r == QUNDEF
  recv
end

# `Hash#initialize_copy`: the other's pairs, default and
# compare_by_identity. The tables are copied as they stand -- a Hash is
# its entries and its bins, and the codes in them were made for the
# same identity rule -- where `replace` would store the pairs one by one.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_hash_initialize_copy(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_HASH || other == recv || RHash.iter(recv) != 0 || zr_frozen_p(recv)
    return zr_send(recv, Machine.id(:replace), 1, argv)
  end
  zr_hash_copy_from(recv, other)
end

# `other`'s tables, default, default proc and compare_by_identity in
# place of the receiver's, with no method of either called: what
# rb_hash_replace and hash_copy do once the checks are made.
sig [Value, Value] => Value
machine def zr_hash_copy_from(recv, other)
  zr_xfree(RHash.entries(recv))
  zr_xfree(RHash.bins(recv))
  RHash.set_entries(recv, 0)
  RHash.set_bins(recv, 0)
  if RHash.entries(other) != 0
    entries = zr_xmalloc(RHash.cap(other) * HEntry.size)
    zr_memcpy(entries, RHash.entries(other), RHash.cap(other) * HEntry.size)
    RHash.set_entries(recv, entries)
    bins = zr_xmalloc(RHash.nbins(other) * 8)
    zr_memcpy(bins, RHash.bins(other), RHash.nbins(other) * 8)
    RHash.set_bins(recv, bins)
  end
  RHash.set_len(recv, RHash.len(other))
  RHash.set_live(recv, RHash.live(other))
  RHash.set_cap(recv, RHash.cap(other))
  RHash.set_nbins(recv, RHash.nbins(other))
  RHash.set_default(recv, RHash.default(other))
  RHash.set_default_proc(recv, RHash.default_proc(other))
  RHash.set_gen(recv, RHash.gen(recv) + 1)
  if (RBasic.flags(other) & FL_IDENTITY) != 0
    RBasic.set_flags(recv, RBasic.flags(recv) | FL_IDENTITY)
  else
    RBasic.set_flags(recv, RBasic.flags(recv) & (0 - FL_IDENTITY - 1))
  end
  recv
end

# rb_hash_dup: a copy of the receiver's class with its pairs, default,
# compare_by_identity and instance variables, made without calling
# `initialize_copy`, as merge and compact start from one.
sig [Value] => Value
machine def zr_hash_dup_m(h)
  copy = zr_copy_cell(h)
  return copy if copy == QUNDEF
  zr_hash_copy_from(copy, h)
end

# A class or module copied: an anonymous one with the same ancestors,
# its own method and constant tables with the same rows, the same
# class-level instance and class variables, and the original's
# singleton methods.
sig [Value] => Value
machine def zr_class_copy(orig)
  klass = zr_type(orig) == T_CLASS ? zr_global(G_CLASS) : zr_global(G_MODULE)
  copy = zr_class_alloc(zr_type(orig), RClass.superclass(orig), klass)
  from = RClass.ext(orig)
  ext = RClass.ext(copy)
  if ClassExt.mlen(from) > 0
    tab = zr_xmalloc(ClassExt.mlen(from) * MEntry.size)
    zr_memcpy(tab, ClassExt.mtab(from), ClassExt.mlen(from) * MEntry.size)
    ClassExt.set_mtab(ext, tab)
    ClassExt.set_mlen(ext, ClassExt.mlen(from))
    zr_methods_changed()
    ClassExt.set_mcap(ext, ClassExt.mlen(from))
  end
  if ClassExt.clen(from) > 0
    tab = zr_xmalloc(ClassExt.clen(from) * CEntry.size)
    zr_memcpy(tab, ClassExt.ctab(from), ClassExt.clen(from) * CEntry.size)
    ClassExt.set_ctab(ext, tab)
    ClassExt.set_clen(ext, ClassExt.clen(from))
    ClassExt.set_ccap(ext, ClassExt.clen(from))
  end
  zr_ivtab_copy(ClassExt.iv(ext), ClassExt.iv(from))
  zr_ivtab_copy(ClassExt.cv(ext), ClassExt.cv(from))
  if zr_type(orig) == T_CLASS
    zr_make_metaclass(copy)
  end
  if zr_singleton_p(RBasic.klass(orig))
    zr_include_singleton(copy, RBasic.klass(orig))
  end
  copy
end

# `clone` for a class that owns its own row and takes no `freeze:`, as
# proc_clone and method_clone take none.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_clone_m(recv, argc, argv, cref, blk)
  zr_obj_clone(recv, Machine.value(QNIL))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_dup(recv, argc, argv, cref, blk)
  if zr_special_p(recv)
    return recv
  end
  if zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE
    return zr_class_copy(recv)
  end
  r = zr_copy_allocatable(recv)
  return r if r == QUNDEF
  copy = zr_copy_cell(recv)
  return copy if copy == QUNDEF
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(copy, Machine.id(:initialize_dup), 1, slot)
  return r if r == QUNDEF
  copy
end

# rb_obj_clone2, under kernel.rb's `clone(freeze: nil)`: the singleton
# class's methods come along, and the frozen bit unless `freeze: false`,
# or with `freeze: true`.
sig [Value, Value] => Value
machine def zr_obj_clone(recv, freeze)
  if freeze != QNIL && freeze != QTRUE && freeze != QFALSE
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("unexpected value for freeze: "), 29)
    zr_buf_class_of(b, freeze)
    return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end
  if zr_special_p(recv)
    if freeze == QFALSE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't unfreeze "), 15)
      zr_buf_class_of(b, recv)
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
    return recv
  end
  if zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE
    copy = zr_class_copy(recv)
  else
    r = zr_copy_allocatable(recv)
    return r if r == QUNDEF
    copy = zr_copy_cell(recv)
    return copy if copy == QUNDEF
    if zr_singleton_p(RBasic.klass(recv))
      zr_include_singleton(copy, RBasic.klass(recv))
    end
  end
  slot = Machine.slot(16)
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(copy, Machine.id(:initialize_clone), 1, slot)
  return r if r == QUNDEF
  if freeze == QTRUE || (freeze == QNIL && zr_frozen_p(recv))
    RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE)
  elsif freeze == QNIL && zr_str_chilled_p(recv)
    # A clone keeps the chill, as rb_obj_clone_setup copies it.
    RBasic.set_flags(copy, RBasic.flags(copy) | (RBasic.flags(recv) & (FL_CHILLED | FL_CHILLED_SYMBOL)))
  end
  copy
end

# The clone's own singleton class, with the original's methods and
# extended modules.
sig [Value, Value] => Void
machine def zr_include_singleton(copy, meta)
  own = zr_singleton_class(copy)
  ext = RClass.ext(meta)
  i = 0
  while i < ClassExt.mlen(ext)
    e = ClassExt.mtab(ext) + (i * MEntry.size)
    zr_method_copy(own, MEntry.mid(e), e, zr_meta_owned_by(MEntry.meta(e), own), MEntry.vis(e), false)
    i += 1
  end
  k = RClass.superclass(meta)
  mods = zr_ary_new(4)
  while k != QNIL && zr_type(k) == T_ICLASS
    zr_ary_push(mods, RClass.attached(k))
    k = RClass.superclass(k)
  end
  i = RArray.len(mods) - 1
  while i >= 0
    zr_include_module(own, zr_ary_at(mods, i))
    i -= 1
  end
end
