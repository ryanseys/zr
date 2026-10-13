# Reflection on names: the instance and class variables of an object,
# and the methods that it responds to.

module Zr::Kern
  # Converts a method or variable name (a Symbol or a String) to its id,
  # and writes the id to `out`.
  #: (value, ptr) -> value
  def zr_name_id(name, out)
    # rb_check_id: any other object that has to_str converts through it,
    # and a to_str that gives no String raises its own TypeError.
    if !zr_special_p(name) && zr_type(name) != T_STRING && !zr_symbol_p(name) &&
       zr_find_method(zr_class_of(name), Machine.id(:to_str)) != 0
      name = zr_str_operand(name)
      return name if name == QUNDEF
    end
    # A name is its bytes and their encoding, as String#to_sym interns it;
    # bytes that are invalid in it raise EncodingError (sym_check_asciionly).
    if !zr_special_p(name) && zr_type(name) == T_STRING
      name = zr_str_to_sym(name, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
      return name if name == QUNDEF
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
  # The NameError has the name as it was given and the receiver.
  #: (value, value, word, ptr, word, ptr, word) -> value
  def zr_bad_variable_name(recv, name, id, sigil, siglen, kind, kindlen)
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
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
    zr_exc_detail(exc, Machine.id(:name), name)
    zr_exc_detail(exc, Machine.id(:receiver), recv)
    zr_exc_raise(exc)
  end

  # Whether the bytes are an identifier: a letter, an underscore or a
  # non-ASCII byte, then any of these or digits.
  #: (ptr, word) -> bool
  def zr_ident_p(p, n)
    if n == 0
      return false
    end
    i = 0
    while i < n
      c = Machine.u8(Machine.load8(p + i, 0))
      alpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
      unless alpha || (i > 0 && c >= 48 && c <= 57)
        return false
      end
      i += 1
    end
    true
  end

  #: (value, value, word) -> value
  def zr_check_ivar_name(recv, name, id)
    zr_bad_variable_name(recv, name, id, Machine.bytes("@"), 1, Machine.bytes("an instance"), 11)
  end

  #: (value, value, word) -> value
  def zr_check_cvar_name(recv, name, id)
    zr_bad_variable_name(recv, name, id, Machine.bytes("@@"), 2, Machine.bytes("a class"), 7)
  end

  # Adds the names in a variable table to `out` as Symbols, with no
  # duplicates. `lead` is the first byte of a name of this kind. It tells a
  # real name from a hidden name that the lowering made.
  #: (ptr, value, word) -> void
  def zr_ivtab_names(t, out, lead)
    i = 0
    while i < IvTab[t].len
      id = IvEntry[IvTab[t].rows + (i * IvEntry.size)].id
      name = zr_sym(id)
      if Machine.u8(Machine.load8(zr_symbol_name_ptr(id), 0)) == lead && zr_ary_index_of(out, name) < 0
        zr_ary_push(out, name)
      end
      i += 1
    end
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_variables(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    t = zr_ivtab(recv)
    if t != 0
      zr_ivtab_names(t, out, 64)
    end
    out
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_variable_get(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    r = zr_ractor_guard(recv)
    return r if r == QUNDEF
    zr_ivar_get(recv, id)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_variable_set(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    r = zr_ractor_guard(recv)
    return r if r == QUNDEF
    zr_ivar_set(recv, id, Machine.value(Machine.load64(argv, 8)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_variable_defined(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    zr_ivar_defined(recv, id)
  end

  # `Module#class_variables`: the module's own class variables, then
  # those of its ancestors when `inherit` is not false.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_variables(recv, argc, argv, cref, blk)
    inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    out = zr_ary_new(4)
    k = recv
    while k != QNIL
      zr_ivtab_names(Machine.ptr(ClassExt[RClass[k].ext].cv), out, 64)
      if inherit
        k = k == recv ? zr_cvar_front(recv) : RClass[k].superclass
      else
        k = Machine.value(QNIL)
      end
    end
    out
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_variable_get(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
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
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_exc_raise(exc)
    end
    zr_ivtab_get(Machine.ptr(ClassExt[RClass[owner].ext].cv), id)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_variable_set(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    owner = zr_cvar_target(recv, id)
    return owner if owner == QUNDEF
    if owner == QNIL
      owner = recv
    end
    r = zr_class_modify_check(zr_cvar_holder(owner))
    return r if r == QUNDEF
    v = Machine.value(Machine.load64(argv, 8))
    zr_ivtab_set(Machine.ptr(ClassExt[RClass[owner].ext].cv), id, v)
    zr_write_barrier(owner, v)
    v
  end

  # `Module#remove_class_variable`: removes the entry from the table of
  # the owning module, and returns its value.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_remove_class_variable(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    r = zr_class_modify_check(recv)
    return r if r == QUNDEF
    t = Machine.ptr(ClassExt[RClass[recv].ext].cv)
    e = zr_ivtab_row(t, id)
    if e == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("class variable "), 15)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" not defined for "), 17)
      zr_buf_class(b, recv)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_exc_raise(exc)
    end
    v = IvEntry[e].value
    last = IvTab[t].rows + ((IvTab[t].len - 1) * IvEntry.size)
    if e != last
      zr_memmove(e, e + IvEntry.size, last - e)
    end
    IvTab[t].len = IvTab[t].len - 1
    zr_obj_ivtab_reembed(recv, t)
    v
  end

  # An object whose entries moved to the heap gets them back in its cell
  # once they fit there again, as CRuby's shape goes back to an embedded
  # one when a removal leaves few enough fields.
  #: (value, ptr) -> void
  def zr_obj_ivtab_reembed(o, t)
    if zr_type(o) != T_OBJECT || zr_ivtab_embedded_p(t)
      return
    end
    cap = (zr_cell_bytes(o) - RObject.size) / IvEntry.size
    if IvTab[t].len > cap
      return
    end
    rows = IvTab[t].rows
    zr_memcpy(t + IvTab.size, rows, IvTab[t].len * IvEntry.size)
    zr_sized_xfree(rows, IvTab[t].cap * IvEntry.size)
    IvTab[t].rows = t + IvTab.size
    IvTab[t].cap = cap
    zr_write_barrier_all(o)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_variable_defined(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_cvar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
    return r if r == QUNDEF
    zr_bool(zr_cvar_owner(recv, id) != QNIL)
  end

  # `Object#singleton_methods`: the public and protected methods of the
  # singleton class, which its origin holds when a module is prepended to
  # it. With `all`, it also includes the methods of the modules that
  # extend it and, for a class, the methods of the singleton classes of
  # its superclasses. A singleton class gets its own singleton class
  # first, so it does not list the one it shares with its class
  # (rb_obj_singleton_methods).
  #: (value, word, ptr, value, value) -> value
  def zr_obj_singleton_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_singleton_names(recv, all, all)
  end

  # The names that `singleton_method` finds: the singleton class's own,
  # and those of the modules that it prepends or that extend the object,
  # but not those of a superclass's singleton class (Bug #20620).
  #: (value) -> value
  def zr_singleton_method_names_m(recv)
    zr_singleton_names(recv, true, false)
  end

  # The singleton class's own names, then with `modules` those of the
  # modules in its list, and with `inherited` those of the superclasses'
  # singleton classes too.
  #: (value, bool, bool) -> value
  def zr_singleton_names(recv, modules, inherited)
    out = zr_ary_new(4)
    seen = zr_ary_new(4)
    if zr_special_p(recv)
      return out
    end
    if zr_type(recv) == T_CLASS && zr_singleton_p(recv)
      made = zr_singleton_class(recv)
      return made if made == QUNDEF
    end
    k = zr_box_view(zr_class_of(recv))
    if !zr_singleton_p(k)
      return out
    end
    origin = zr_origin(k)
    zr_level_method_names(origin, out, seen, 0 - 1)
    if modules
      k = RClass[k].superclass
      while k != QNIL && (zr_type(k) == T_ICLASS || k == origin || (inherited && zr_singleton_p(k)))
        if k != origin
          zr_level_method_names(k, out, seen, 0 - 1)
        end
        k = RClass[k].superclass
      end
    end
    out
  end

  # `methods`, and the three forms for each visibility. `methods(false)`
  # is the same as `singleton_methods(false)`.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_methods(recv, argc, argv, cref, blk)
    if argc == 1 && (Machine.value(Machine.load64(argv, 0)) == QFALSE || Machine.value(Machine.load64(argv, 0)) == QNIL)
      return zr_obj_singleton_methods(recv, argc, argv, cref, blk)
    end
    zr_method_names(zr_class_of(recv), 1, 0 - 1, true)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_public_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PUBLIC, true)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_private_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PRIVATE, true)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_protected_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PROTECTED, true)
  end

  # `method_defined?` and the three forms for each visibility: whether the
  # module or an ancestor defines the name with that visibility (-1 for
  # public or protected, -2 for any). An active refinement does not count,
  # because the check uses only the module's own ancestor list. `max` is
  # the most arguments the form takes.
  #: (value, word, ptr, word, word) -> value
  def zr_mod_method_defined_vis(recv, argc, argv, vis, max)
    if argc < 1 || argc > max
      return zr_wrong_arity_range(argc, 1, max)
    end
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    inherit = argc < 2 || (Machine.value(Machine.load64(argv, 8)) != QFALSE && Machine.value(Machine.load64(argv, 8)) != QNIL)
    # A class with a prepended module keeps its own methods in its origin.
    e = inherit ? zr_search_method(recv, Machine.load64(slot, 0)) : zr_find_method_at(zr_origin(recv), Machine.load64(slot, 0))
    if e == 0 || MEntry[e].kind == KIND_UNDEF || zr_entry_hidden_p(e) || MEntry[e].fn == Machine.addr(:zr_f_notimplement)
      return Machine.value(QFALSE)
    end
    zr_bool(vis == 0 - 2 || (vis < 0 ? MEntry[e].vis != VIS_PRIVATE : MEntry[e].vis == vis))
  end

  # `method_defined?(name, inherit = true, include_private = false)`: the
  # third argument also matches a private method (ruby 4.1).
  #: (value, word, ptr, value, value) -> value
  def zr_mod_method_defined(recv, argc, argv, cref, blk)
    any = argc == 3 && Machine.value(Machine.load64(argv, 16)) != QFALSE && Machine.value(Machine.load64(argv, 16)) != QNIL
    zr_mod_method_defined_vis(recv, argc, argv, any ? 0 - 2 : 0 - 1, 3)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PUBLIC, 2)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_private_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PRIVATE, 2)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_protected_method_defined(recv, argc, argv, cref, blk)
    zr_mod_method_defined_vis(recv, argc, argv, VIS_PROTECTED, 2)
  end

  # The function of the method that `klass` finds for `name`, as a
  # number, or 0 when it finds none. It stays the same while the method
  # does, so comparing it is a test, with no allocation, that a program
  # did not redefine or remove a core method.
  #: (value, value) -> value
  def zr_method_fn_m(klass, name)
    e = zr_find_method(klass, zr_sym2id(name))
    if e == 0 || MEntry[e].kind == KIND_UNDEF
      return zr_fix(0)
    end
    zr_fix(Machine.word(MEntry[e].fn))
  end

  # `Method#super_method`: the method after this method's owner in the
  # receiver's ancestor list, bound in the same way, or nil.
  #: (value, word, ptr, value, value) -> value
  def zr_method_super_method(recv, argc, argv, cref, blk)
    owner = RMethod[recv].owner
    # An alias searches on under its original name, as CRuby's
    # method_super_method reads def->original_id.
    mid = zr_method_original_id(Machine.ptr(RMethod[recv].entry))
    k = RMethod[recv].klass
    while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass[k].attached == owner))
      k = RClass[k].superclass
    end
    if k == QNIL
      return Machine.value(QNIL)
    end
    # A class with a prepended module keeps its methods in its origin, and
    # the search goes on above that.
    if zr_type(k) != T_ICLASS
      k = zr_origin(k)
    end
    # A visibility copy (a zsuper entry) searches on after the node of its
    # original. So does an alias of a module's method, whose entry keeps
    # the iclass (rb_alias sets defined_class only for one); an alias of a
    # superclass's method searches on from its own class.
    e = Machine.ptr(RMethod[recv].entry)
    from = MEntry[e].from
    if from != QNIL && (zr_type(from) == T_ICLASS || MEntry[e].mid == MEntry[e].orig)
      k = from
    end
    sup = RClass[k].superclass
    if sup == QNIL
      return Machine.value(QNIL)
    end
    e = zr_find_method(sup, mid)
    # A visibility copy with nothing above it names no method.
    if e == 0 || MEntry[e].kind == KIND_UNDEF || MEntry[e].kind == KIND_MISSING
      return Machine.value(QNIL)
    end
    zr_method_new(RMethod[recv].recv, sup, mid)
  end

  # `Module#included_modules`: the modules in the ancestor list, nearest
  # first.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_included_modules(recv, argc, argv, cref, blk)
    out = zr_ary_new(8)
    k = RClass[recv].superclass
    while k != QNIL
      if zr_type(k) == T_ICLASS && RClass[k].origin == QNIL && k != RClass[recv].origin && zr_type(RClass[k].attached) == T_MODULE
        zr_ary_push(out, RClass[k].attached)
      end
      k = RClass[k].superclass
    end
    out
  end

  # `Module.nesting`: the classes and modules whose bodies enclose the
  # caller, innermost first. An eval's cref is not lexical, so it is
  # skipped.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_nesting(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    # rb_vm_cref reads the nearest frame of Ruby code. A call from the
    # core (`Fiber.new(&Module.method(:nesting))`) has none: no nesting.
    rec = zr_frame_with_file(Frame[Task[zr_task()].top].prev)
    if rec == 0
      return out
    end
    c = Frame[rec].cref
    while c != QNIL && c != zr_global(G_TOP_CREF)
      if RCref[c].eval == 0
        zr_ary_push(out, zr_cref_klass(c))
      end
      c = RCref[c].next
    end
    out
  end

  # `__method__`: the name of the method that contains the caller, through
  # any blocks, or nil at the top level or in a class body. A define_method
  # body is a block whose cref refers to its method entry. Its name is the
  # name that define_method gave, also when it is called through an alias.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_method_name(recv, argc, argv, cref, blk)
    rec = Frame[Task[zr_task()].top].prev
    e = zr_bmethod_entry(rec)
    if e != 0
      return zr_sym(FrameMeta[MEntry[e].meta].name)
    end
    meta = Frame[rec].meta
    while (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL) && FrameMeta[meta].parent != 0
      meta = FrameMeta[meta].parent
    end
    # A def in the core library runs with a builtin's FrameMeta.
    if FrameMeta[meta].kind != KIND_DEF && FrameMeta[meta].kind != KIND_BUILTIN
      return Machine.value(QNIL)
    end
    zr_sym(FrameMeta[meta].name)
  end

  # `__callee__`: the name that the caller used for the method. For an
  # alias, it is the alias name.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_callee(recv, argc, argv, cref, blk)
    rec = Frame[Task[zr_task()].top].prev
    start = rec
    e = zr_bmethod_entry(rec)
    if e != 0
      return zr_sym(MEntry[e].mid)
    end
    meta = Frame[rec].meta
    while (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL) && FrameMeta[meta].parent != 0
      meta = FrameMeta[meta].parent
      rec = Frame[rec].prev
      while rec != 0 && Frame[rec].meta != meta
        rec = Frame[rec].prev
      end
      if rec == 0
        # The method has returned. Its Env, which the block keeps, has the
        # name that the call used; else the name of its def is left.
        while (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL) && FrameMeta[meta].parent != 0
          meta = FrameMeta[meta].parent
        end
        if FrameMeta[meta].kind != KIND_DEF
          return Machine.value(QNIL)
        end
        kept = zr_env_callee(start)
        return zr_sym(kept != 0 ? kept : FrameMeta[meta].name)
      end
    end
    # A runtime method written in Ruby runs as a builtin. An alias can call
    # it, as for a method of the program.
    if FrameMeta[meta].kind != KIND_DEF && FrameMeta[meta].kind != KIND_BUILTIN
      return Machine.value(QNIL)
    end
    mid = zr_frame_mid(rec)
    if mid == 0
      return zr_sym(FrameMeta[meta].name)
    end
    zr_sym(mid)
  end

  # The name that the call of a returned method used, from the Env at the
  # root of the Env chain of the block frame `rec`, or 0.
  #: (ptr) -> word
  def zr_env_callee(rec)
    if !zr_block_frame_p(rec) || Frame[rec].entry == 0
      return 0
    end
    env = RProc[Frame[rec].entry].env
    if env == QNIL
      return 0
    end
    while REnv[env].parent != QNIL
      env = REnv[env].parent
    end
    REnv[env].mid
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_singleton_class_p(recv, argc, argv, cref, blk)
    zr_bool(zr_singleton_p(recv))
  end

  # `Proc#source_location`: the location of the block in the source, or
  # nil for a block that the runtime made.
  #: (value, word, ptr, value, value) -> value
  def zr_proc_source_location(recv, argc, argv, cref, blk)
    # The location of a Method's Proc is the location of the method.
    if RProc[recv].fn == Machine.addr(:zr_method_block)
      return zr_send(RProc[recv].self, Machine.id(:source_location), 0, 0)
    end
    meta = RProc[recv].meta
    if meta == 0 || FrameMeta[meta].file_len == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_meta_path(meta))
    zr_ary_push(out, zr_fix(FrameMeta[meta].line))
    out
  end

  # The singleton methods of the main object: `include`, `public` and
  # `private` operate on Object.
  #: (value, word, ptr, value, value) -> value
  def zr_main_include(recv, argc, argv, cref, blk)
    zr_send(zr_global(G_OBJECT), Machine.id(:include), argc, argv)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_main_public(recv, argc, argv, cref, blk)
    zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PUBLIC, 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_main_private(recv, argc, argv, cref, blk)
    zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PRIVATE, 0)
  end

  # `Module#remove_method`: the method entry must be in the module's own
  # table.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_remove_method(recv, argc, argv, cref, blk)
    i = 0
    while i < argc
      slot = Machine.slot(8)
      r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
      return r if r == QUNDEF
      # rb_mod_remove_method: each name converts first, then the module is
      # checked, so no name checks nothing.
      r = zr_class_modify_check(recv)
      return r if r == QUNDEF
      mid = Machine.load64(slot, 0)
      zr_warn_removing(mid)
      klass = zr_origin(recv)
      e = zr_find_method_at(klass, mid)
      if e == 0 || MEntry[e].kind == KIND_UNDEF
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("method '"), 8)
        zr_buf_sym(b, mid)
        zr_buf_push(b, Machine.bytes("' not defined in "), 17)
        zr_buf_str(b, zr_class_to_s(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
        exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
        zr_exc_detail(exc, Machine.id(:name), zr_sym(mid))
        zr_exc_detail(exc, Machine.id(:receiver), recv)
        return zr_exc_raise(exc)
      end
      zr_warn_operator(recv, mid, e)
      ext = RClass[klass].ext
      zr_save_core_row(ext, e)
      last = ClassExt[ext].mtab + ((ClassExt[ext].mlen - 1) * MEntry.size)
      if e != last
        zr_memmove(e, e + MEntry.size, last - e)
      end
      ClassExt[ext].mlen = ClassExt[ext].mlen - 1
      zr_method_index_drop(ext)
      zr_methods_changed()
      zr_vis_copies_drop(klass, mid)
      zr_vis_copies_resolve(mid)
      zr_gates_recheck(mid)
      r = zr_method_removed(recv, mid)
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # Calls the `method_removed` or `singleton_method_removed` hook, if the
  # program defines it.
  #: (value, word) -> value
  def zr_method_removed(klass, mid)
    zr_method_hook(klass, mid, Machine.id(:method_removed), Machine.id(:singleton_method_removed))
  end

  #: (value, word) -> value
  def zr_method_undefined(klass, mid)
    zr_method_hook(klass, mid, Machine.id(:method_undefined), Machine.id(:singleton_method_undefined))
  end

  # Calls `hook` on the class, or `singleton_hook` on the object that a
  # singleton class is attached to, if the program defines it.
  #: (value, word, word, word) -> value
  def zr_method_hook(klass, mid, hook, singleton_hook)
    recv = klass
    if zr_singleton_p(klass)
      recv = RClass[klass].attached
      hook = singleton_hook
    end
    if zr_find_method(zr_class_of(recv), hook) == 0
      return Machine.value(QNIL)
    end
    zr_hook(recv, hook, zr_sym(mid))
  end

  # `remove_instance_variable(name)`: removes the ivar entry and returns
  # its value.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_remove_instance_variable(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_check_ivar_name(recv, Machine.value(Machine.load64(argv, 0)), id)
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
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_exc_raise(exc)
    end
    v = IvEntry[e].value
    last = IvTab[t].rows + ((IvTab[t].len - 1) * IvEntry.size)
    if e != last
      zr_memmove(e, e + IvEntry.size, last - e)
    end
    IvTab[t].len = IvTab[t].len - 1
    v
  end

  # `Class#subclasses`: the classes whose superclass is this class, newest
  # first, with no singleton classes. It reads them from the arena and
  # sorts them by creation serial.
  #: (value, word, ptr, value, value) -> value
  def zr_class_subclasses(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    a = 0
    while a < Heap[zr_heap()].arenas
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead[base].cell
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
  #: (value, value) -> void
  def zr_ary_insert_by_serial(out, k)
    serial = ClassExt[RClass[k].ext].serial
    n = RArray[out].len
    zr_ary_push(out, k)
    i = 0
    while i < n && ClassExt[RClass[zr_ary_at(out, i)].ext].serial > serial
      i += 1
    end
    j = n
    while j > i
      zr_ary_store(out, j, zr_ary_at(out, j - 1))
      j -= 1
    end
    zr_ary_store(out, i, k)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_main_define_method(recv, argc, argv, cref, blk)
    zr_mod_define_method(zr_global(G_OBJECT), argc, argv, cref, blk)
  end

  # The main object's `to_s` and `inspect`, which are singleton methods
  # that return `main`.
  #: (value, word, ptr, value, value) -> value
  def zr_main_to_s(recv, argc, argv, cref, blk)
    zr_str_set_index(zr_str_new(Machine.bytes("main"), 4), ENC_BINARY)
  end

  # `attached_object`: the object that a singleton class belongs to. A
  # plain class has no attached object.
  #: (value) -> value
  def zr_mod_attached(klass)
    if !zr_singleton_p(klass)
      return Machine.value(QNIL)
    end
    RClass[klass].attached
  end

  # Returns the FrameMeta of the Ruby code that a Proc, a Method or an
  # UnboundMethod runs, or 0 for runtime code. RubyVM::InstructionSequence.of
  # finds an instruction sequence only when this is not 0.
  #: (value) -> ptr
  def zr_iseq_meta(body)
    if zr_special_p(body)
      return 0
    end
    meta = 0
    if zr_type(body) == T_PROC
      if RProc[body].fn == Machine.addr(:zr_method_block)
        return zr_iseq_meta(RProc[body].self)
      end
      meta = RProc[body].meta
    elsif zr_type(body) == T_METHOD
      meta = zr_method_location(Machine.ptr(RMethod[body].entry))
    end
    if meta == 0 || FrameMeta[meta].file_len == 0 || FrameMeta[meta].kind == KIND_BUILTIN || FrameMeta[meta].kind == KIND_HIDDEN
      return 0
    end
    meta
  end

  #: (value) -> value
  def zr_iseq_p(body)
    zr_bool(zr_iseq_meta(body) != 0)
  end

  # Returns the label of the code that `body` runs. With `base`, it
  # returns the label of the method, class or file that contains the
  # blocks.
  #: (value, value) -> value
  def zr_iseq_label(body, base)
    zr_iseq_meta_label(zr_fix(Machine.word(zr_iseq_meta(body))), base)
  end

  # The same for the FrameMeta at address `meta_word`, in the form that a
  # frame gives it.
  #: (value, value) -> value
  def zr_iseq_meta_label(meta_word, base)
    meta = Machine.ptr(zr_fix2long(meta_word))
    if meta == 0
      return Machine.value(QNIL)
    end
    if base == QTRUE
      while FrameMeta[meta].kind == KIND_BLOCK
        meta = FrameMeta[meta].parent
      end
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_label_as(b, meta, false)
    zr_buf_take(b)
  end

  # Returns `[path, first line, kind, last line]` of the FrameMeta at
  # `meta_word`. The kind is the name that RubyVM::InstructionSequence#type
  # gives.
  #: (value) -> value
  def zr_iseq_meta_info(meta_word)
    meta = Machine.ptr(zr_fix2long(meta_word))
    out = zr_ary_new(4)
    zr_ary_push(out, zr_meta_file(meta))
    kind = FrameMeta[meta].kind
    # ruby makes the code of a whole file (rb_iseq_new_main, _top) with
    # first line 0.
    zr_ary_push(out, zr_fix(kind == KIND_MAIN || kind == KIND_TOP ? 0 : FrameMeta[meta].line))
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
    zr_ary_push(out, zr_fix(FrameMeta[meta].end_line))
    out
  end

  # Returns the parameter list of the FrameMeta at `meta_word`: for a
  # method, as a method takes them; for a block, as a proc takes them.
  #: (value) -> value
  def zr_iseq_meta_parameters(meta_word)
    meta = Machine.ptr(zr_fix2long(meta_word))
    zr_iseq_meta_parameters_as(meta_word, zr_bool(FrameMeta[meta].kind == KIND_BLOCK))
  end

  # The same, as a proc takes them when `as_proc` is true, else as a
  # method or a lambda takes them (rb_iseq_parameters).
  #: (value, value) -> value
  def zr_iseq_meta_parameters_as(meta_word, as_proc)
    meta = Machine.ptr(zr_fix2long(meta_word))
    if FrameMeta[meta].params == 0
      return zr_ary_new(0)
    end
    zr_param_rows(FrameMeta[meta].params, as_proc == QTRUE)
  end

  #: (value) -> value
  def zr_iseq_meta_word(body)
    zr_fix(Machine.word(zr_iseq_meta(body)))
  end

  # Whether the code of `meta` is a C method's, as ruby sees it: a
  # builtin, or a core method that zr writes in Ruby and ruby in C. Its
  # frame has no file and no line of its own.
  #: (ptr) -> bool
  def zr_meta_native_p(meta)
    FrameMeta[meta].kind == KIND_BUILTIN || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].file_len == 0
  end

  # What rb_profile_frame_* reads of the code of the FrameMeta at
  # `meta_word` (a frame of rb_profile_frames), besides what its
  # instruction sequence gives: `[form, owner, name]`. The form is :cfunc
  # for a C method (zr_meta_native_p), :method for a Ruby method, and
  # :code for other code: a block outside a method, a class body, a file.
  #: (value) -> value
  def zr_profile_meta(meta_word)
    meta = Machine.ptr(zr_fix2long(meta_word))
    form = Machine.id(:code)
    if zr_meta_native_p(meta)
      form = Machine.id(:cfunc)
    elsif FrameMeta[meta].kind == KIND_DEF
      form = Machine.id(:method)
    end
    out = zr_ary_new(3)
    zr_ary_push(out, zr_sym(form))
    zr_ary_push(out, FrameMeta[meta].owner)
    zr_ary_push(out, FrameMeta[meta].name == 0 ? Machine.value(QNIL) : zr_sym(FrameMeta[meta].name))
    out
  end

  # The frames that a debugger reads, outward from the caller of this
  # method, as zr_debug_frames_from gives them.
  #: () -> value
  def zr_debug_frames
    zr_debug_frames_from(Frame[Task[zr_task()].top].prev)
  end

  # The data that rb_debug_inspector_open gives a debugger. It returns
  # each shown frame, from `rec` outward, as `[backtrace line, node id,
  # self, binding, FrameMeta address, class, method entry address]`. A
  # frame that the runtime pushed for a C method has no binding, and its
  # address is 0.
  #: (ptr) -> value
  def zr_debug_frames_from(rec)
    out = zr_ary_new(16)
    while rec != 0
      if zr_frame_shown_p(rec)
        entry = zr_ary_new(7)
        zr_ary_push(out, entry)
        meta = Frame[rec].meta
        native = zr_meta_native_p(meta)
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        # A C frame has no file or line of its own.
        if native
          zr_buf_push(b, Machine.bytes(":0:in '"), 7)
          zr_buf_label(b, zr_frame_label_meta(rec))
          zr_buf_byte(b, 39)
        else
          zr_buf_frame(b, rec, 0)
        end
        zr_ary_push(entry, zr_frame_text(b, rec))
        source = zr_frame_with_file(rec)
        zr_ary_push(entry, zr_fix(source == 0 || native ? 0 : zr_frame_node_id(source)))
        zr_ary_push(entry, Frame[rec].self)
        if native
          zr_ary_push(entry, Machine.value(QNIL))
          zr_ary_push(entry, zr_fix(0))
        else
          blk = zr_block_proc(Frame[rec].blk)
          bound = zr_binding_of(meta, zr_frame_env(rec), Frame[rec].self, Frame[rec].cref)
          RProc[bound].blk = blk
          RProc[bound].serial = zr_frame_line(rec)
          zr_ary_push(entry, bound)
          zr_ary_push(entry, zr_fix(Machine.word(meta)))
        end
        method = zr_method_meta_of(rec)
        zr_ary_push(entry, method == 0 ? Machine.value(QNIL) : FrameMeta[method].owner)
        zr_ary_push(entry, zr_fix(Machine.word(Frame[rec].entry)))
      end
      rec = Frame[rec].prev
    end
    out
  end
end
