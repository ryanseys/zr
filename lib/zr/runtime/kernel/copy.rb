# `dup` and `clone`: a new cell with the same contents, its own copies
# of the memory that the cell owns outside the arena, then
# `initialize_copy`. A clone keeps the frozen bit and the singleton
# class. A dup keeps neither.

module Zr::Kern
  # Copies the ivar entries of one table into a new table. The object id,
  # and the mark that a core class puts on a cell it built, stay with the
  # original.
  #: (ptr, ptr, value) -> void
  def zr_ivtab_copy(to, from, owner)
    IvTab.set_len(to, 0)
    IvTab.set_names(to, 0)
    i = 0
    while i < IvTab.len(from)
      e = IvTab.rows(from) + (i * IvEntry.size)
      if IvEntry.id(e) != Machine.id(:__object_id__) && IvEntry.id(e) != Machine.id(:__built__)
        zr_ivtab_set_in(to, IvEntry.id(e), IvEntry.value(e), owner)
      end
      i += 1
    end
  end

  # Makes the memory that the copy owns. A String, an Array or a Hash
  # starts empty, as with CRuby's allocator. Its `initialize_copy` fills
  # it. Thus a subclass whose `initialize_copy` does not call `super`
  # copies nothing, as in ruby.
  #: (value, value) -> value
  def zr_copy_payload(copy, orig)
    t = zr_type(orig)
    if t == T_OBJECT
      # The copy has the cell's bytes, including the ivar entries pointer.
      zr_obj_ivtab_init(copy)
      zr_ivtab_copy(RObject.iv(copy), RObject.iv(orig), copy)
      zr_write_barrier_all(copy)
    elsif t == T_STRING
      zr_str_buf_new(copy, 0)
      Machine.store8(RString.ptr(copy), 0, Machine.i8(0))
      RString.set_len(copy, 0)
    elsif t == T_ARRAY
      zr_ary_buf_new(copy, 0)
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
        zr_write_barrier_all(copy)
      end
    elsif t == T_FIBER
      # CRuby copies a Fiber's fields but not its machine stack. Thus the
      # copy is a fiber that was never set up: it has no context, no stack
      # and no task, and it refuses to run.
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
      RRegexp.set_names(copy, Machine.value(QNIL))
      RRegexp.set_options(copy, 0)
      RRegexp.set_program(copy, Machine.value(QNIL))
      RRegexp.set_alt(copy, Machine.value(QNIL))
    elsif t != T_PROC && t != T_METHOD
      # The cell already contains the original's words. Clear them, or the
      # collector frees the original's memory when the copy dies.
      Libc.memset(Machine.ptr(copy) + RBasic.size, Machine.i32(0), zr_cell_bytes(copy) - RBasic.size)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't copy this kind of object"), 30)
    end
    if (RBasic.flags(orig) & FL_EXIVAR) != 0
      zr_ivtab_copy(zr_exivar_tab_for_write(copy), zr_exivar_tab(orig), Machine.value(QNIL))
    zr_write_barrier_all(copy)
    end
    copy
  end

  # Copies the cell, with its own payload and with the real class. The
  # caller decides to keep or drop the frozen bit and the singleton class.
  #: (value) -> value
  def zr_copy_cell(orig)
    bytes = zr_cell_bytes(orig)
    copy = zr_alloc(zr_type(orig), zr_real_class(orig), bytes)
    zr_memcpy(Machine.ptr(copy) + RBasic.size, Machine.ptr(orig) + RBasic.size, bytes - RBasic.size)
    zr_copy_payload(copy, orig)
  end

  # A copy starts as `allocate` would make it, so a class with no
  # allocator cannot be copied: a Thread, an Encoding. A Proc, a Method
  # and a Binding use their own copy rules.
  #: (value) -> value
  def zr_copy_allocatable(recv)
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

  # `Array#initialize_copy`, which fills a `dup` or a `clone`. It puts the
  # other Array's elements in place of the receiver's, as `replace` does.
  # A non-Array goes through `replace` itself, which converts it.
  #: (value, word, ptr, value, value) -> value
  def zr_ary_initialize_copy(recv, argc, argv, cref, blk)
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

  # `String#initialize_copy`: copies the other String's bytes and encoding.
  #: (value, word, ptr, value, value) -> value
  def zr_str_initialize_copy(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_STRING
      return zr_send(recv, Machine.id(:replace), 1, argv)
    end
    r = zr_str_replace(recv, other)
    return r if r == QUNDEF
    recv
  end

  # `Hash#initialize_copy`: copies the other Hash's pairs, default and
  # compare_by_identity. It copies the tables as they are: a Hash is its
  # entries and its bins, and their hash codes use the same identity rule.
  # `replace` would store the pairs one at a time.
  #: (value, word, ptr, value, value) -> value
  def zr_hash_initialize_copy(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_HASH || other == recv || RHash.iter(recv) != 0 || zr_frozen_p(recv)
      return zr_send(recv, Machine.id(:replace), 1, argv)
    end
    zr_hash_copy_from(recv, other)
  end

  # Puts the tables, default, default proc and compare_by_identity of
  # `other` in place of the receiver's, and calls no method on either.
  # This is what rb_hash_replace and hash_copy do after their checks.
  #: (value, value) -> value
  def zr_hash_copy_from(recv, other)
    zr_sized_xfree(RHash.entries(recv), RHash.cap(recv) * HEntry.size)
    zr_sized_xfree(RHash.bins(recv), RHash.nbins(recv) * 8)
    RHash.set_entries(recv, 0)
    RHash.set_bins(recv, 0)
    if RHash.entries(other) != 0
      entries = zr_xmalloc(RHash.cap(other) * HEntry.size)
      zr_memcpy(entries, RHash.entries(other), RHash.cap(other) * HEntry.size)
      RHash.set_entries(recv, entries)
      if RHash.nbins(other) != 0
        bins = zr_xmalloc(RHash.nbins(other) * 8)
        zr_memcpy(bins, RHash.bins(other), RHash.nbins(other) * 8)
        RHash.set_bins(recv, bins)
      end
    end
    RHash.set_len(recv, RHash.len(other))
    RHash.set_live(recv, RHash.live(other))
    RHash.set_cap(recv, RHash.cap(other))
    RHash.set_nbins(recv, RHash.nbins(other))
    RHash.set_default(recv, RHash.default(other))
    RHash.set_default_proc(recv, RHash.default_proc(other))
    RHash.set_gen(recv, RHash.gen(recv) + 1)
    zr_write_barrier_all(recv)
    if (RBasic.flags(other) & FL_IDENTITY) != 0
      RBasic.set_flags(recv, RBasic.flags(recv) | FL_IDENTITY)
    else
      RBasic.set_flags(recv, RBasic.flags(recv) & (0 - FL_IDENTITY - 1))
    end
    recv
  end

  # rb_hash_dup: a copy of the receiver's class with its pairs, default,
  # compare_by_identity and instance variables. It does not call
  # `initialize_copy`. merge and compact start from such a copy.
  #: (value) -> value
  def zr_hash_dup_m(h)
    copy = zr_copy_cell(h)
    return copy if copy == QUNDEF
    zr_hash_copy_from(copy, h)
  end

  # Copies a class or module. The copy is anonymous, with the same
  # ancestors, its own method and constant tables with the same entries,
  # the same class-level instance and class variables, and the original's
  # singleton methods.
  #: (value) -> value
  def zr_class_copy(orig)
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
    zr_ivtab_copy(ClassExt.iv(ext), ClassExt.iv(from), Machine.value(QNIL))
    zr_ivtab_copy(ClassExt.cv(ext), ClassExt.cv(from), Machine.value(QNIL))
    zr_write_barrier_all(copy)
    if zr_type(orig) == T_CLASS
      zr_make_metaclass(copy)
    end
    if zr_singleton_p(RBasic.klass(orig))
      zr_include_singleton(copy, RBasic.klass(orig))
    end
    copy
  end

  # `clone` for a class that has its own `clone` method entry and takes no
  # `freeze:`, as proc_clone and method_clone take none.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_clone_m(recv, argc, argv, cref, blk)
    zr_obj_clone(recv, Machine.value(QNIL))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_dup(recv, argc, argv, cref, blk)
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

  # rb_obj_clone2, called by kernel.rb's `clone(freeze: nil)`. The clone
  # gets the singleton class's methods. It gets the frozen bit unless
  # `freeze: false`, and always with `freeze: true`.
  #: (value, value) -> value
  def zr_obj_clone(recv, freeze)
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
      # A clone keeps the chilled flag, as rb_obj_clone_setup copies it.
      RBasic.set_flags(copy, RBasic.flags(copy) | (RBasic.flags(recv) & (FL_CHILLED | FL_CHILLED_SYMBOL)))
    end
    copy
  end

  # The clone's own singleton class, with the original's methods and
  # extended modules.
  #: (value, value) -> void
  def zr_include_singleton(copy, meta)
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
end
