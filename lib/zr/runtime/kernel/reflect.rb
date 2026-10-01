# Reflection on names: the instance and class variables of an object,
# and the methods that it responds to.

module Zr::Kern
  # Converts a method or variable name (a Symbol or a String) to its id,
  # and writes the id to `out`.
  sig [Value, Ptr] => Value
  def zr_name_id(name, out)
    if !zr_special_p(name) && zr_type(name) == T_STRING
      name = zr_sym(zr_intern(RString.ptr(name), RString.len(name)))
    end
    unless zr_symbol_p(name)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      s = zr_inspect(name)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_push(b, Machine.bytes(" is not a symbol nor a string"), 29)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    Machine.store64(out, 0, zr_sym2id(name))
    Machine.value(QNIL)
  end

  # Raises `'x' is not allowed as an instance variable name`, or the class
  # variable form, when the name does not start with its sigil.
  sig [Word, Ptr, Word, Ptr, Word] => Value
  def zr_bad_variable_name(id, sigil, siglen, kind, kindlen)
    p = zr_symbol_name_ptr(id)
    n = zr_symbol_name_len(id)
    if n > siglen && zr_bytes_eq(p, siglen, sigil, siglen) && zr_ident_p(p + siglen, n - siglen)
      return Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("'"), 1)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes("' is not allowed as "), 20)
    zr_buf_push(b, kind, kindlen)
    zr_buf_push(b, Machine.bytes(" variable name"), 14)
    zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end

  # Whether the bytes are an identifier: a letter, an underscore or a
  # non-ASCII byte, then any of these or digits.
  sig [Ptr, Word] => Bool
  def zr_ident_p(p, n)
    if n == 0
      return false
    end
    i = 0
    while i < n
      c = Machine.word(Machine.load8(p + i, 0))
      alpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
      unless alpha || (i > 0 && c >= 48 && c <= 57)
        return false
      end
      i += 1
    end
    true
  end

  sig [Word] => Value
  def zr_check_ivar_name(id)
    zr_bad_variable_name(id, Machine.bytes("@"), 1, Machine.bytes("an instance"), 11)
  end

  sig [Word] => Value
  def zr_check_cvar_name(id)
    zr_bad_variable_name(id, Machine.bytes("@@"), 2, Machine.bytes("a class"), 7)
  end

  # Adds the names in a variable table to `out` as Symbols, with no
  # duplicates. `lead` is the first byte of a name of this kind. It tells a
  # real name from a hidden name that the lowering made.
  sig [Ptr, Value, Word] => Void
  def zr_ivtab_names(t, out, lead)
    i = 0
    while i < IvTab.len(t)
      id = IvEntry.id(IvTab.rows(t) + (i * IvEntry.size))
      name = zr_sym(id)
      if Machine.word(Machine.load8(zr_symbol_name_ptr(id), 0)) == lead && zr_ary_index_of(out, name) < 0
        zr_ary_push(out, name)
      end
      i += 1
    end
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_instance_variables(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    t = zr_ivtab(recv)
    if t != 0
      zr_ivtab_names(t, out, 64)
    end
    out
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_instance_variable_get(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(id)
    return r if r == QUNDEF
    r = zr_ractor_guard(recv)
    return r if r == QUNDEF
    zr_ivar_get(recv, id)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_instance_variable_set(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(id)
    return r if r == QUNDEF
    r = zr_ractor_guard(recv)
    return r if r == QUNDEF
    zr_ivar_set(recv, id, Machine.value(Machine.load64(argv, 8)))
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_instance_variable_defined(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(id)
    return r if r == QUNDEF
    zr_ivar_defined(recv, id)
  end

  # `Module#class_variables`: the module's own class variables, then
  # those of its ancestors when `inherit` is not false.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_class_variables(recv, argc, argv, cref, blk)
    inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    out = zr_ary_new(4)
    k = recv
    while k != QNIL
      zr_ivtab_names(ClassExt.cv(RClass.ext(k)), out, 64)
      if inherit
        k = RClass.superclass(k)
      else
        k = Machine.value(QNIL)
      end
    end
    out
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_class_variable_get(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(id)
    return r if r == QUNDEF
    owner = zr_cvar_target(recv, id)
    return owner if owner == QUNDEF
    if owner == QNIL
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("uninitialized class variable "), 29)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" in "), 4)
      zr_buf_class(b, recv)
      return zr_raise_buf(zr_global(G_NAME_ERROR), b)
    end
    zr_ivtab_get(ClassExt.cv(RClass.ext(owner)), id)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_class_variable_set(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(id)
    return r if r == QUNDEF
    owner = zr_cvar_target(recv, id)
    return owner if owner == QUNDEF
    if owner == QNIL
      owner = recv
    end
    r = zr_class_modify_check(owner)
    return r if r == QUNDEF
    v = Machine.value(Machine.load64(argv, 8))
    zr_ivtab_set(ClassExt.cv(RClass.ext(owner)), id, v)
    zr_write_barrier(owner, v)
    v
  end

  # `Module#remove_class_variable`: removes the entry from the table of
  # the owning module, and returns its value.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_remove_class_variable(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(id)
    return r if r == QUNDEF
    r = zr_class_modify_check(recv)
    return r if r == QUNDEF
    t = ClassExt.cv(RClass.ext(recv))
    e = zr_ivtab_row(t, id)
    if e == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("class variable "), 15)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" not defined for "), 17)
      zr_buf_class(b, recv)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_raise(exc)
    end
    v = IvEntry.value(e)
    last = IvTab.rows(t) + ((IvTab.len(t) - 1) * IvEntry.size)
    if e != last
      zr_memmove(e, e + IvEntry.size, last - e)
    end
    IvTab.set_len(t, IvTab.len(t) - 1)
    v
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_class_variable_defined(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(id)
    return r if r == QUNDEF
    zr_bool(zr_cvar_owner(recv, id) != QNIL)
  end

  # `Object#singleton_methods`: the public and protected methods of the
  # singleton class. With `all`, it also includes the methods of the
  # modules that extend it and, for a class, the methods of the singleton
  # classes of its superclasses.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_singleton_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    out = zr_ary_new(4)
    seen = zr_ary_new(4)
    if zr_special_p(recv)
      return out
    end
    k = zr_box_view(zr_class_of(recv))
    if !zr_singleton_p(k)
      return out
    end
    zr_level_method_names(k, out, seen, 0 - 1)
    if all
      k = RClass.superclass(k)
      while k != QNIL && (zr_type(k) == T_ICLASS || zr_singleton_p(k))
        zr_level_method_names(k, out, seen, 0 - 1)
        k = RClass.superclass(k)
      end
    end
    out
  end

  # `methods`, and the three forms for each visibility. `methods(false)`
  # is the same as `singleton_methods(false)`.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_methods(recv, argc, argv, cref, blk)
    if argc == 1 && (Machine.value(Machine.load64(argv, 0)) == QFALSE || Machine.value(Machine.load64(argv, 0)) == QNIL)
      return zr_obj_singleton_methods(recv, argc, argv, cref, blk)
    end
    zr_method_names(zr_class_of(recv), 1, 0 - 1, true)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_public_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PUBLIC, true)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_private_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PRIVATE, true)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_protected_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PROTECTED, true)
  end

  # `method_defined?` and the three forms for each visibility: whether the
  # module or an ancestor defines the name with that visibility. An active
  # refinement does not count, because the check uses only the module's
  # own ancestor list.
  sig [Value, Word, Ptr, Word] => Value
  def zr_mod_method_defined_vis(recv, argc, argv, vis)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    inherit = argc < 2 || (Machine.value(Machine.load64(argv, 8)) != QFALSE && Machine.value(Machine.load64(argv, 8)) != QNIL)
    e = inherit ? zr_search_method(recv, Machine.load64(slot, 0)) : zr_find_method_at(recv, Machine.load64(slot, 0))
    if e == 0 || MEntry.kind(e) == KIND_UNDEF || zr_entry_hidden_p(e) || MEntry.fn(e) == Machine.addr(:zr_f_notimplement)
      return Machine.value(QFALSE)
    end
    zr_bool(vis < 0 ? MEntry.vis(e) != VIS_PRIVATE : MEntry.vis(e) == vis)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, 0 - 1)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_public_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PUBLIC)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_private_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PRIVATE)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_protected_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PROTECTED)
  end

  # `Method#super_method`: the method after this method's owner in the
  # receiver's ancestor list, bound in the same way, or nil.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_method_super_method(recv, argc, argv, cref, blk)
    owner = RMethod.owner(recv)
    mid = MEntry.mid(RMethod.entry(recv))
    k = RMethod.klass(recv)
    while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass.attached(k) == owner))
      k = RClass.superclass(k)
    end
    if k == QNIL
      return Machine.value(QNIL)
    end
    sup = RClass.superclass(k)
    if sup == QNIL
      return Machine.value(QNIL)
    end
    e = zr_find_method(sup, mid)
    if e == 0 || MEntry.kind(e) == KIND_UNDEF
      return Machine.value(QNIL)
    end
    zr_method_new(RMethod.recv(recv), sup, mid)
  end

  # `Module#included_modules`: the modules in the ancestor list, nearest
  # first.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_included_modules(recv, argc, argv, cref, blk)
    out = zr_ary_new(8)
    k = RClass.superclass(recv)
    while k != QNIL
      if zr_type(k) == T_ICLASS && RClass.origin(k) == QNIL && k != RClass.origin(recv) && zr_type(RClass.attached(k)) == T_MODULE
        zr_ary_push(out, RClass.attached(k))
      end
      k = RClass.superclass(k)
    end
    out
  end

  # `Module.nesting`: the classes and modules whose bodies enclose the
  # caller, innermost first. An eval's cref is not lexical, so it is
  # skipped.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_nesting(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    c = Frame.cref(Frame.prev(Task.top(zr_task())))
    while c != QNIL && c != zr_global(G_TOP_CREF)
      if RCref.eval(c) == 0
        zr_ary_push(out, zr_cref_klass(c))
      end
      c = RCref.next(c)
    end
    out
  end

  # `__method__`: the name of the method that contains the caller, through
  # any blocks, or nil at the top level or in a class body. A define_method
  # body is a block whose cref refers to its method entry. Its name is the
  # name that define_method gave, also when it is called through an alias.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_kernel_method_name(recv, argc, argv, cref, blk)
    rec = Frame.prev(Task.top(zr_task()))
    e = zr_bmethod_entry(rec)
    if e != 0
      return zr_sym(FrameMeta.name(MEntry.meta(e)))
    end
    meta = Frame.meta(rec)
    while (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.kind(meta) == KIND_EVAL) && FrameMeta.parent(meta) != 0
      meta = FrameMeta.parent(meta)
    end
    # A def in the core library runs with a builtin's FrameMeta.
    if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BMETHOD && FrameMeta.kind(meta) != KIND_BUILTIN
      return Machine.value(QNIL)
    end
    zr_sym(FrameMeta.name(meta))
  end

  # `__callee__`: the name that the caller used for the method. For an
  # alias, it is the alias name.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_kernel_callee(recv, argc, argv, cref, blk)
    rec = Frame.prev(Task.top(zr_task()))
    e = zr_bmethod_entry(rec)
    if e != 0
      return zr_sym(MEntry.mid(e))
    end
    meta = Frame.meta(rec)
    while (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.kind(meta) == KIND_EVAL) && FrameMeta.parent(meta) != 0
      meta = FrameMeta.parent(meta)
      rec = Frame.prev(rec)
      while rec != 0 && Frame.meta(rec) != meta
        rec = Frame.prev(rec)
      end
      if rec == 0
        return Machine.value(QNIL)
      end
    end
    # A runtime method written in Ruby runs as a builtin. An alias can call
    # it, as for a method of the program.
    if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BMETHOD && FrameMeta.kind(meta) != KIND_BUILTIN
      return Machine.value(QNIL)
    end
    mid = zr_frame_mid(rec)
    if mid == 0
      return zr_sym(FrameMeta.name(meta))
    end
    zr_sym(mid)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_singleton_class_p(recv, argc, argv, cref, blk)
    zr_bool(zr_singleton_p(recv))
  end

  # `Proc#source_location`: the location of the block in the source, or
  # nil for a block that the runtime made.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_proc_source_location(recv, argc, argv, cref, blk)
    # The location of a Method's Proc is the location of the method.
    if RProc.fn(recv) == Machine.addr(:zr_method_block)
      return zr_send(RProc.self(recv), Machine.id(:source_location), 0, 0)
    end
    meta = RProc.meta(recv)
    if meta == 0 || FrameMeta.file_len(meta) == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta)))
    zr_ary_push(out, zr_fix(FrameMeta.line(meta)))
    out
  end

  # The singleton methods of the main object: `include`, `public` and
  # `private` operate on Object.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_main_include(recv, argc, argv, cref, blk)
    zr_send(zr_global(G_OBJECT), Machine.id(:include), argc, argv)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_main_public(recv, argc, argv, cref, blk)
    zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PUBLIC, 0)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_main_private(recv, argc, argv, cref, blk)
    zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PRIVATE, 0)
  end

  # `Module#remove_method`: the method entry must be in the module's own
  # table.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_mod_remove_method(recv, argc, argv, cref, blk)
    r = zr_class_modify_check(recv)
    return r if r == QUNDEF
    i = 0
    while i < argc
      slot = Machine.slot(8)
      r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
      return r if r == QUNDEF
      mid = Machine.load64(slot, 0)
      klass = zr_origin(recv)
      e = zr_find_method_at(klass, mid)
      if e == 0 || MEntry.kind(e) == KIND_UNDEF
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("method '"), 8)
        zr_buf_sym(b, mid)
        zr_buf_push(b, Machine.bytes("' not defined in "), 17)
        zr_buf_str(b, zr_class_to_s(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
        exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
        zr_exc_detail(exc, Machine.id(:name), zr_sym(mid))
        zr_exc_detail(exc, Machine.id(:receiver), recv)
        return zr_raise(exc)
      end
      zr_warn_operator(recv, mid, e)
      ext = RClass.ext(klass)
      zr_save_core_row(ext, e)
      last = ClassExt.mtab(ext) + ((ClassExt.mlen(ext) - 1) * MEntry.size)
      if e != last
        zr_memmove(e, e + MEntry.size, last - e)
      end
      ClassExt.set_mlen(ext, ClassExt.mlen(ext) - 1)
      zr_method_index_drop(ext)
      zr_methods_changed()
      zr_gates_recheck(mid)
      r = zr_method_removed(recv, mid)
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # Calls the `method_removed` or `singleton_method_removed` hook, if the
  # program defines it.
  sig [Value, Word] => Value
  def zr_method_removed(klass, mid)
    zr_method_hook(klass, mid, Machine.id(:method_removed), Machine.id(:singleton_method_removed))
  end

  sig [Value, Word] => Value
  def zr_method_undefined(klass, mid)
    zr_method_hook(klass, mid, Machine.id(:method_undefined), Machine.id(:singleton_method_undefined))
  end

  # Calls `hook` on the class, or `singleton_hook` on the object that a
  # singleton class is attached to, if the program defines it.
  sig [Value, Word, Word, Word] => Value
  def zr_method_hook(klass, mid, hook, singleton_hook)
    recv = klass
    if zr_singleton_p(klass)
      recv = RClass.attached(klass)
      hook = singleton_hook
    end
    if zr_find_method(zr_class_of(recv), hook) == 0
      return Machine.value(QNIL)
    end
    zr_hook(recv, hook, zr_sym(mid))
  end

  # `remove_instance_variable(name)`: removes the ivar entry and returns
  # its value.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_remove_instance_variable(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(id)
    return r if r == QUNDEF
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    t = zr_ivtab(recv)
    e = 0
    if t != 0
      e = zr_ivtab_row(t, id)
    end
    if e == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("instance variable "), 18)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" not defined"), 12)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_raise(exc)
    end
    v = IvEntry.value(e)
    last = IvTab.rows(t) + ((IvTab.len(t) - 1) * IvEntry.size)
    if e != last
      zr_memmove(e, e + IvEntry.size, last - e)
    end
    IvTab.set_len(t, IvTab.len(t) - 1)
    v
  end

  # `Class#subclasses`: the classes whose superclass is this class, newest
  # first, with no singleton classes. It reads them from the arena and
  # sorts them by creation serial.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_class_subclasses(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    a = 0
    while a < Heap.arenas(zr_heap())
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead.cell(base)
      i = zr_arena_next_allocated(base, 0)
      while i < ARENA_CELLS
        cell = first + (i * bytes)
        flags = Machine.load64(cell, 0)
        if (flags & T_MASK) == T_CLASS && (flags & (FL_SINGLETON | FL_CONCEALED)) == 0
          k = Machine.value(cell)
          if k != recv && zr_real_superclass(k) == recv
            zr_ary_insert_by_serial(out, k)
          end
        end
        i = zr_arena_next_allocated(base, i + 1)
      end
      a += 1
    end
    out
  end

  # Inserts `k` before the first class that was made before `k`.
  sig [Value, Value] => Void
  def zr_ary_insert_by_serial(out, k)
    serial = ClassExt.serial(RClass.ext(k))
    n = RArray.len(out)
    zr_ary_push(out, k)
    i = 0
    while i < n && ClassExt.serial(RClass.ext(zr_ary_at(out, i))) > serial
      i += 1
    end
    j = n
    while j > i
      zr_ary_store(out, j, zr_ary_at(out, j - 1))
      j -= 1
    end
    zr_ary_store(out, i, k)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_main_define_method(recv, argc, argv, cref, blk)
    zr_mod_define_method(zr_global(G_OBJECT), argc, argv, cref, blk)
  end

  # The main object's `to_s` and `inspect`, which are singleton methods
  # that return `main`.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_main_to_s(recv, argc, argv, cref, blk)
    zr_str_set_index(zr_str_new(Machine.bytes("main"), 4), ENC_BINARY)
  end

  # `attached_object`: the object that a singleton class belongs to. A
  # plain class has no attached object.
  sig [Value] => Value
  def zr_mod_attached(klass)
    if !zr_singleton_p(klass)
      return Machine.value(QNIL)
    end
    RClass.attached(klass)
  end

  # Returns the FrameMeta of the Ruby code that a Proc, a Method or an
  # UnboundMethod runs, or 0 for runtime code. RubyVM::InstructionSequence.of
  # finds an instruction sequence only when this is not 0.
  sig [Value] => Ptr
  def zr_iseq_meta(body)
    if zr_special_p(body)
      return 0
    end
    meta = 0
    if zr_type(body) == T_PROC
      if RProc.fn(body) == Machine.addr(:zr_method_block)
        return zr_iseq_meta(RProc.self(body))
      end
      meta = RProc.meta(body)
    elsif zr_type(body) == T_METHOD
      meta = zr_method_location(RMethod.entry(body))
    end
    if meta == 0 || FrameMeta.file_len(meta) == 0 || FrameMeta.kind(meta) == KIND_BUILTIN || FrameMeta.kind(meta) == KIND_HIDDEN
      return 0
    end
    meta
  end

  sig [Value] => Value
  def zr_iseq_p(body)
    zr_bool(zr_iseq_meta(body) != 0)
  end

  # Returns the label of the code that `body` runs. With `base`, it
  # returns the label of the method, class or file that contains the
  # blocks.
  sig [Value, Value] => Value
  def zr_iseq_label(body, base)
    zr_iseq_meta_label(zr_fix(Machine.word(zr_iseq_meta(body))), base)
  end

  # The same for the FrameMeta at address `meta_word`, in the form that a
  # frame gives it.
  sig [Value, Value] => Value
  def zr_iseq_meta_label(meta_word, base)
    meta = Machine.ptr(zr_fix2long(meta_word))
    if meta == 0
      return Machine.value(QNIL)
    end
    if base == QTRUE
      while FrameMeta.kind(meta) == KIND_BLOCK
        meta = FrameMeta.parent(meta)
      end
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_label_as(b, meta, false)
    zr_buf_take(b)
  end

  # Returns `[path, first line, kind]` of the FrameMeta at `meta_word`.
  # The kind is the name that RubyVM::InstructionSequence#type gives.
  sig [Value] => Value
  def zr_iseq_meta_info(meta_word)
    meta = Machine.ptr(zr_fix2long(meta_word))
    out = zr_ary_new(3)
    zr_ary_push(out, zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta)))
    zr_ary_push(out, zr_fix(FrameMeta.line(meta)))
    kind = FrameMeta.kind(meta)
    name = Machine.id(:top)
    if kind == KIND_DEF
      name = Machine.id(:method)
    elsif kind == KIND_BLOCK
      name = Machine.id(:block)
    elsif kind == KIND_CLASS || kind == KIND_MODULE || kind == KIND_SCLASS
      name = Machine.id(:class)
    elsif kind == KIND_MAIN
      name = Machine.id(:main)
    elsif kind == KIND_EVAL || kind == KIND_COMPILED
      name = Machine.id(:eval)
    end
    zr_ary_push(out, zr_sym(name))
    out
  end

  # Returns the parameter list of the FrameMeta at `meta_word`: for a
  # method, as a method takes them; for a block, as a proc takes them.
  sig [Value] => Value
  def zr_iseq_meta_parameters(meta_word)
    meta = Machine.ptr(zr_fix2long(meta_word))
    if FrameMeta.params(meta) == 0
      return zr_ary_new(0)
    end
    zr_param_rows(FrameMeta.params(meta), FrameMeta.kind(meta) == KIND_BLOCK)
  end

  sig [Value] => Value
  def zr_iseq_meta_word(body)
    zr_fix(Machine.word(zr_iseq_meta(body)))
  end

  # The data that rb_debug_inspector_open gives a debugger. It returns
  # each frame, outward from the caller of this method, as `[backtrace
  # line, node id, self, binding, FrameMeta address, class]`. A frame that
  # the runtime pushed for a C method has no binding, and its address is 0.
  sig [] => Value
  def zr_debug_frames
    out = zr_ary_new(16)
    rec = Frame.prev(Task.top(zr_task()))
    while rec != 0
      if zr_frame_shown_p(rec)
        entry = zr_ary_new(6)
        zr_ary_push(out, entry)
        meta = Frame.meta(rec)
        native = FrameMeta.kind(meta) == KIND_BUILTIN || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.file_len(meta) == 0
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        # A C frame has no file or line of its own.
        if native
          zr_buf_push(b, Machine.bytes(":0:in '"), 7)
          zr_buf_label(b, zr_frame_label_meta(rec))
          zr_buf_byte(b, 39)
        else
          zr_buf_frame(b, rec)
        end
        zr_ary_push(entry, zr_buf_take(b))
        source = zr_frame_with_file(rec)
        zr_ary_push(entry, zr_fix(source == 0 || native ? 0 : zr_frame_node_id(source)))
        zr_ary_push(entry, Frame.self(rec))
        if native
          zr_ary_push(entry, Machine.value(QNIL))
          zr_ary_push(entry, zr_fix(0))
        else
          blk = zr_block_proc(Frame.blk(rec))
          bound = zr_binding_of(meta, zr_frame_env(rec), Frame.self(rec), Frame.cref(rec))
          RProc.set_blk(bound, blk)
          RProc.set_serial(bound, zr_frame_line(rec))
          zr_ary_push(entry, bound)
          zr_ary_push(entry, zr_fix(Machine.word(meta)))
        end
        method = zr_method_meta_of(rec)
        zr_ary_push(entry, method == 0 ? Machine.value(QNIL) : FrameMeta.owner(method))
      end
      rec = Frame.prev(rec)
    end
    out
  end
end
