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
    IvTab[to].len = 0
    IvTab[to].names = 0
    i = 0
    while i < IvTab[from].len
      e = IvTab[from].rows + (i * IvEntry.size)
      if IvEntry[e].id != Machine.id(:__object_id__) && IvEntry[e].id != Machine.id(:__built__)
        zr_ivtab_set_in(to, IvEntry[e].id, IvEntry[e].value, owner)
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
      zr_ivtab_copy(Machine.ptr(RObject[copy].iv), Machine.ptr(RObject[orig].iv), copy)
      zr_write_barrier_all(copy)
    elsif t == T_STRING
      zr_str_buf_new(copy, 0)
      Machine.store8(RString[copy].ptr, 0, Machine.i8(0))
      RString[copy].len = 0
    elsif t == T_ARRAY
      zr_ary_buf_new(copy, 0)
    elsif t == T_HASH
      RHash[copy].entries = 0
      RHash[copy].len = 0
      RHash[copy].live = 0
      RHash[copy].cap = 0
      RHash[copy].default = Machine.value(QNIL)
      RHash[copy].default_proc = Machine.value(QNIL)
      RHash[copy].bins = 0
      RHash[copy].nbins = 0
      RHash[copy].iter = 0
      RHash[copy].gen = 0
    elsif t == T_EXCEPTION
      if RException[orig].rows != 0
        rows = zr_xmalloc(RException[orig].nrows * BtRow.size)
        zr_memcpy(rows, RException[orig].rows, RException[orig].nrows * BtRow.size)
        RException[copy].rows = rows
        zr_write_barrier_all(copy)
      end
    elsif t == T_FIBER
      # CRuby copies a Fiber's fields but not its machine stack. Thus the
      # copy is a fiber that was never set up: it has no context, no stack
      # and no task, and it refuses to run.
      RFiber[copy].task = 0
      RFiber[copy].ctx = 0
      RFiber[copy].stack = 0
      RFiber[copy].kroots = 0
      RFiber[copy].blk = Machine.value(QNIL)
      RFiber[copy].status = FIBER_CREATED
      RFiber[copy].prev = Machine.value(QNIL)
      RFiber[copy].resuming = Machine.value(QNIL)
      RFiber[copy].value = Machine.value(QNIL)
      RFiber[copy].yielding = 0
      RFiber[copy].transferred = 0
    elsif t == T_REGEXP
      RRegexp[copy].source = Machine.value(QNIL)
      RRegexp[copy].names = Machine.value(QNIL)
      RRegexp[copy].options = 0
      RRegexp[copy].program = Machine.value(QNIL)
      RRegexp[copy].alt = Machine.value(QNIL)
    elsif t != T_PROC && t != T_METHOD
      # The cell already contains the original's words. Clear them, or the
      # collector frees the original's memory when the copy dies.
      Libc.memset(Machine.ptr(copy) + RBasic.size, Machine.i32(0), zr_cell_bytes(copy) - RBasic.size)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't copy this kind of object"), 30)
    end
    if (RBasic[orig].flags & FL_EXIVAR) != 0
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
    r = zr_ary_splice(recv, zr_fix(0), zr_fix(RArray[recv].len), other)
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
    if zr_special_p(other) || zr_type(other) != T_HASH || other == recv || RHash[recv].iter != 0 || zr_frozen_p(recv)
      return zr_send(recv, Machine.id(:replace), 1, argv)
    end
    zr_hash_copy_from(recv, other)
  end

  # Puts the tables, default, default proc and compare_by_identity of
  # `other` in place of the receiver's, and calls no method on either.
  # This is what rb_hash_replace and hash_copy do after their checks.
  #: (value, value) -> value
  def zr_hash_copy_from(recv, other)
    zr_sized_xfree(RHash[recv].entries, RHash[recv].cap * HEntry.size)
    zr_sized_xfree(RHash[recv].bins, RHash[recv].nbins * 8)
    RHash[recv].entries = 0
    RHash[recv].bins = 0
    if RHash[other].entries != 0
      entries = zr_xmalloc(RHash[other].cap * HEntry.size)
      zr_memcpy(entries, RHash[other].entries, RHash[other].cap * HEntry.size)
      RHash[recv].entries = entries
      if RHash[other].nbins != 0
        bins = zr_xmalloc(RHash[other].nbins * 8)
        zr_memcpy(bins, RHash[other].bins, RHash[other].nbins * 8)
        RHash[recv].bins = bins
      end
    end
    RHash[recv].len = RHash[other].len
    RHash[recv].live = RHash[other].live
    RHash[recv].cap = RHash[other].cap
    RHash[recv].nbins = RHash[other].nbins
    RHash[recv].default = RHash[other].default
    RHash[recv].default_proc = RHash[other].default_proc
    RHash[recv].gen = RHash[recv].gen + 1
    zr_write_barrier_all(recv)
    if (RBasic[other].flags & FL_IDENTITY) != 0
      RBasic[recv].flags = RBasic[recv].flags | FL_IDENTITY
    else
      RBasic[recv].flags = RBasic[recv].flags & (0 - FL_IDENTITY - 1)
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
    # class_init_copy_check: BasicObject has no copy.
    if orig == zr_global(G_BASIC_OBJECT)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't copy the root class"), 25)
    end
    if zr_singleton_p(orig)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't copy singleton class"), 26)
    end
    klass = zr_type(orig) == T_CLASS ? zr_global(G_CLASS) : zr_global(G_MODULE)
    copy = zr_class_alloc(zr_type(orig), RClass[orig].superclass, klass)
    from = RClass[orig].ext
    ext = RClass[copy].ext
    if ClassExt[from].mlen > 0
      tab = zr_xmalloc(ClassExt[from].mlen * MEntry.size)
      zr_memcpy(tab, ClassExt[from].mtab, ClassExt[from].mlen * MEntry.size)
      ClassExt[ext].mtab = tab
      ClassExt[ext].mlen = ClassExt[from].mlen
      zr_methods_changed()
      ClassExt[ext].mcap = ClassExt[from].mlen
      zr_crefs_rebound(tab, ClassExt[ext].mlen, orig, copy)
    end
    if ClassExt[from].clen > 0
      tab = zr_xmalloc(ClassExt[from].clen * CEntry.size)
      zr_memcpy(tab, ClassExt[from].ctab, ClassExt[from].clen * CEntry.size)
      ClassExt[ext].ctab = tab
      ClassExt[ext].clen = ClassExt[from].clen
      ClassExt[ext].ccap = ClassExt[from].clen
    end
    zr_ivtab_copy(Machine.ptr(ClassExt[ext].iv), Machine.ptr(ClassExt[from].iv), Machine.value(QNIL))
    zr_ivtab_copy(Machine.ptr(ClassExt[ext].cv), Machine.ptr(ClassExt[from].cv), Machine.value(QNIL))
    if RClass[orig].origin != QNIL
      zr_class_copy_prepends(copy, orig)
    end
    zr_write_barrier_all(copy)
    if zr_type(orig) == T_CLASS
      zr_make_metaclass(copy)
      # rb_class_init_copy: the copy allocates as the original does, so a
      # copy of String makes Strings.
      ClassExt[ext].alloc = zr_alloc_kind(orig)
    end
    if zr_singleton_p(RBasic[orig].klass)
      zr_include_singleton(copy, RBasic[orig].klass)
    end
    copy
  end

  # rb_vm_rewrite_cref: a copied method whose body was written in the
  # original reads constants and class variables through the copy, so
  # `def foo = TEST` in a clone finds the clone's own TEST.
  #: (ptr, word, value, value) -> void
  def zr_crefs_rebound(tab, len, orig, copy)
    i = 0
    while i < len
      e = tab + (i * MEntry.size)
      cref = MEntry[e].cref
      if !zr_special_p(cref) && zr_type(cref) == T_CREF && RCref[cref].klass == orig
        MEntry[e].cref = zr_cref_push(copy, RCref[cref].next)
      end
      i += 1
    end
  end

  # rb_mod_init_copy for a class or module with prepends: the copy gets
  # an origin of its own with the original origin's methods, and a proxy
  # of its own for each module between the original and its origin. A
  # proxy of a module that has an origin gets the copy of that origin.
  #: (value, value) -> void
  def zr_class_copy_prepends(copy, orig)
    oo = RClass[orig].origin
    RClass[copy].superclass = RClass[oo].superclass
    zr_ensure_origin(copy)
    co = RClass[copy].origin
    from = RClass[oo].ext
    ext = RClass[co].ext
    if ClassExt[from].mlen > 0
      tab = zr_xmalloc(ClassExt[from].mlen * MEntry.size)
      zr_memcpy(tab, ClassExt[from].mtab, ClassExt[from].mlen * MEntry.size)
      ClassExt[ext].mtab = tab
      ClassExt[ext].mlen = ClassExt[from].mlen
      ClassExt[ext].mcap = ClassExt[from].mlen
    end
    # Pairs of [the copy of a proxy, the original origin of that proxy].
    waiting = zr_ary_new(2)
    prev = copy
    p = RClass[orig].superclass
    while p != oo && p != QNIL
      ic = zr_iclass_new(p, Machine.value(QNIL))
      RClass[prev].superclass = ic
      if RClass[p].origin != QNIL && RClass[p].origin != p
        zr_ary_push(waiting, ic)
        zr_ary_push(waiting, RClass[p].origin)
      end
      i = 0
      while i < RArray[waiting].len
        if zr_ary_at(waiting, i + 1) == p
          RClass[zr_ary_at(waiting, i)].origin = ic
        end
        i += 2
      end
      prev = ic
      p = RClass[p].superclass
    end
    RClass[prev].superclass = co
    zr_methods_changed()
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
      # The copy is whole before initialize_dup runs, so the hook sees its
      # ancestors (Bug #21538).
      copy = zr_class_copy(recv)
      return copy if copy == QUNDEF
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(recv))
      r = zr_send(copy, Machine.id(:initialize_dup), 1, slot)
      return r if r == QUNDEF
      return copy
    end
    r = zr_copy_allocatable(recv)
    return r if r == QUNDEF
    copy = zr_copy_cell(recv)
    return copy if copy == QUNDEF
    zr_copy_finalizers(copy, recv)
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
      return copy if copy == QUNDEF
    else
      r = zr_copy_allocatable(recv)
      return r if r == QUNDEF
      copy = zr_copy_cell(recv)
      return copy if copy == QUNDEF
      zr_copy_finalizers(copy, recv)
      if zr_singleton_p(RBasic[recv].klass)
        zr_include_singleton(copy, RBasic[recv].klass)
      end
    end
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(recv))
    # rb_obj_clone_setup: a freeze: given to clone goes on to
    # initialize_clone as a keyword.
    if freeze == QNIL
      r = zr_send(copy, Machine.id(:initialize_clone), 1, slot)
    else
      h = zr_hash_new()
      zr_hash_store(h, zr_sym(Machine.id(:freeze)), freeze)
      Machine.store64(slot, 8, Machine.word(h))
      zr_kw_pass()
      r = zr_send(copy, Machine.id(:initialize_clone), 2, slot)
    end
    return r if r == QUNDEF
    if freeze == QTRUE || (freeze == QNIL && zr_frozen_p(recv))
      RBasic[copy].flags = RBasic[copy].flags | FL_FREEZE
    elsif freeze == QNIL && zr_str_chilled_p(recv)
      # A clone keeps the chilled flag, as rb_obj_clone_setup copies it.
      RBasic[copy].flags = RBasic[copy].flags | (RBasic[recv].flags & (FL_CHILLED | FL_CHILLED_SYMBOL))
    end
    copy
  end

  # The clone's own singleton class, with the original's methods and
  # extended modules.
  #: (value, value) -> void
  def zr_include_singleton(copy, meta)
    own = zr_singleton_class(copy)
    ext = RClass[meta].ext
    i = 0
    while i < ClassExt[ext].mlen
      e = ClassExt[ext].mtab + (i * MEntry.size)
      zr_method_copy(own, MEntry[e].mid, e, zr_meta_owned_by(MEntry[e].meta, own), MEntry[e].vis, false)
      i += 1
    end
    # rb_singleton_class_clone copies the constants too.
    i = 0
    while i < ClassExt[ext].clen
      c = ClassExt[ext].ctab + (i * CEntry.size)
      zr_const_write(own, CEntry[c].id, CEntry[c].value)
      i += 1
    end
    k = RClass[meta].superclass
    mods = zr_ary_new(4)
    while k != QNIL && zr_type(k) == T_ICLASS
      zr_ary_push(mods, RClass[k].attached)
      k = RClass[k].superclass
    end
    i = RArray[mods].len - 1
    while i >= 0
      zr_include_module(own, zr_ary_at(mods, i))
      i -= 1
    end
    # rb_singleton_class_clone clones the singleton class's own singleton
    # class too, with its methods.
    outer = RBasic[meta].klass
    if zr_singleton_p(outer) && RClass[outer].attached == meta
      zr_include_singleton(own, outer)
    end
  end
end
