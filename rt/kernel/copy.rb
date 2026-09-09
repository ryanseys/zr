# `dup` and `clone`: a fresh cell with the same contents, its own
# copies of what the cell owns outside the arena, then
# `initialize_copy`. A clone keeps the frozen bit and the singleton
# class; a dup keeps neither.

# The rows of one ivar table copied into another, fresh, table; the
# object id and the mark a core class puts on a cell it has built
# stay with the original.
sig [Ptr, Ptr] => Void
machine def zr_ivtab_copy(to, from)
  zr_ivtab_init(to)
  i = 0
  while i < IvTab.len(from)
    e = IvTab.rows(from) + (i * IvEntry.size)
    if IvEntry.id(e) != Machine.id(:__object_id__) && IvEntry.id(e) != Machine.id(:__built__)
      zr_ivtab_set(to, IvEntry.id(e), IvEntry.value(e))
    end
    i += 1
  end
end

# What the copy owns: buffers and tables of its own, with the same
# contents.
sig [Value, Value] => Value
machine def zr_copy_payload(copy, orig)
  t = zr_type(orig)
  if t == T_OBJECT
    zr_ivtab_copy(RObject.iv(copy), RObject.iv(orig))
  elsif t == T_STRING
    buf = malloc(RString.len(orig) + 1)
    zr_memcpy(buf, RString.ptr(orig), RString.len(orig) + 1)
    RString.set_ptr(copy, buf)
    RString.set_capa(copy, RString.len(orig) + 1)
  elsif t == T_ARRAY
    n = RArray.len(orig)
    capa = n < 4 ? 4 : n
    buf = malloc(capa * 8)
    zr_memcpy(buf, RArray.ptr(orig), n * 8)
    RArray.set_ptr(copy, buf)
    RArray.set_capa(copy, capa)
  elsif t == T_HASH
    if RHash.entries(orig) != 0
      entries = malloc(RHash.cap(orig) * HEntry.size)
      zr_memcpy(entries, RHash.entries(orig), RHash.cap(orig) * HEntry.size)
      RHash.set_entries(copy, entries)
      bins = malloc(RHash.nbins(orig) * 8)
      zr_memcpy(bins, RHash.bins(orig), RHash.nbins(orig) * 8)
      RHash.set_bins(copy, bins)
    end
    RHash.set_iter(copy, 0)
  elsif t == T_EXCEPTION
    if RException.rows(orig) != 0
      rows = malloc(RException.nrows(orig) * BtRow.size)
      zr_memcpy(rows, RException.rows(orig), RException.nrows(orig) * BtRow.size)
      RException.set_rows(copy, rows)
    end
  elsif t == T_REGEXP
    RRegexp.set_reg(copy, 0)
    r = zr_send(copy, Machine.id(:recompile), 0, 0)
    return r if r == QUNDEF
  elsif t != T_PROC && t != T_METHOD
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
  RBasic.set_flags(copy, RBasic.flags(copy) | (RBasic.flags(orig) & FL_BINARY))
  zr_copy_payload(copy, orig)
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
    tab = malloc(ClassExt.mlen(from) * MEntry.size)
    zr_memcpy(tab, ClassExt.mtab(from), ClassExt.mlen(from) * MEntry.size)
    ClassExt.set_mtab(ext, tab)
    ClassExt.set_mlen(ext, ClassExt.mlen(from))
    ClassExt.set_mcap(ext, ClassExt.mlen(from))
  end
  if ClassExt.clen(from) > 0
    tab = malloc(ClassExt.clen(from) * CEntry.size)
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

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_dup(recv, argc, argv, cref, blk)
  if zr_special_p(recv)
    return recv
  end
  if zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE
    return zr_class_copy(recv)
  end
  copy = zr_copy_cell(recv)
  return copy if copy == QUNDEF
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(copy, Machine.id(:initialize_dup), 1, slot)
  return r if r == QUNDEF
  copy
end

# `clone(freeze: nil)`: the singleton class's methods come along, and
# the frozen bit unless `freeze: false`, or with `freeze: true`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_clone(recv, argc, argv, cref, blk)
  freeze = Machine.value(QNIL)
  if zr_kw_take() != 0
    opts = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    argc -= 1
    known = Machine.slot(8)
    Machine.store64(known, 0, Machine.id(:freeze))
    r = zr_kw_unknown(opts, known, 1)
    return r if r == QUNDEF
    freeze = zr_hash_lookup(opts, zr_sym(Machine.id(:freeze)))
    if freeze == QUNDEF
      freeze = Machine.value(QNIL)
    elsif freeze != QNIL && freeze != QTRUE && freeze != QFALSE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("unexpected value for freeze: "), 29)
      zr_buf_str(b, zr_class_name_of(freeze))
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
  end
  if argc > 0
    return zr_wrong_arity(argc, 0)
  end
  if zr_special_p(recv)
    if freeze == QFALSE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't unfreeze "), 15)
      zr_buf_str(b, zr_class_name_of(recv))
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
    return recv
  end
  if zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE
    copy = zr_class_copy(recv)
  else
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
