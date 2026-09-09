# Reflection over names: the instance and class variables an object
# holds, and the methods it answers to.

# A method or variable name given as a Symbol or a String, as its id
# in `out`.
sig [Value, Ptr] => Value
machine def zr_name_id(name, out)
  if !zr_special_p(name) && zr_type(name) == T_STRING
    name = zr_sym(zr_intern(RString.ptr(name), RString.len(name)))
  end
  unless zr_symbol_p(name)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    s = zr_send(name, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    zr_buf_push(b, Machine.bytes(" is not a symbol nor a string"), 29)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.store64(out, 0, zr_sym2id(name))
  Machine.value(QNIL)
end

# `'x' is not allowed as an instance variable name`, and the class
# variable form, when the name lacks its sigil.
sig [Word, Ptr, Word, Ptr, Word] => Value
machine def zr_bad_variable_name(id, sigil, siglen, kind, kindlen)
  p = zr_symbol_name_ptr(id)
  n = zr_symbol_name_len(id)
  if n > siglen && zr_bytes_eq(p, siglen, sigil, siglen) && Machine.word(Machine.load8(p + siglen, 0)) != 64
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

sig [Word] => Value
machine def zr_check_ivar_name(id)
  zr_bad_variable_name(id, Machine.bytes("@"), 1, Machine.bytes("an instance"), 11)
end

sig [Word] => Value
machine def zr_check_cvar_name(id)
  zr_bad_variable_name(id, Machine.bytes("@@"), 2, Machine.bytes("a class"), 7)
end

# The names in a variable table, as Symbols, each once, after those
# already in `out`; a hidden one stays out.
sig [Ptr, Value] => Void
machine def zr_ivtab_names(t, out)
  i = 0
  while i < IvTab.len(t)
    id = IvEntry.id(IvTab.rows(t) + (i * IvEntry.size))
    name = zr_sym(id)
    if zr_ivar_id_visible_p(id) && zr_ary_index_of(out, name) < 0
      zr_ary_push(out, name)
    end
    i += 1
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_variables(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  t = zr_ivtab(recv)
  if t != 0
    zr_ivtab_names(t, out)
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_variable_get(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_ivar_name(id)
  return r if r == QUNDEF
  zr_ivar_get(recv, id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_variable_set(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_ivar_name(id)
  return r if r == QUNDEF
  zr_ivar_set(recv, id, Machine.value(Machine.load64(argv, 8)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_variable_defined(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_ivar_name(id)
  return r if r == QUNDEF
  zr_ivar_defined(recv, id)
end

# `Module#class_variables`: the module's own, then its ancestors' when
# `inherit` is not false.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_variables(recv, argc, argv, cref, blk)
  inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  out = zr_ary_new(4)
  k = recv
  while k != QNIL
    zr_ivtab_names(ClassExt.cv(RClass.ext(k)), out)
    if inherit
      k = RClass.superclass(k)
    else
      k = Machine.value(QNIL)
    end
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_variable_get(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_cvar_name(id)
  return r if r == QUNDEF
  owner = zr_cvar_owner(recv, id)
  if owner == QNIL
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("uninitialized class variable "), 29)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" in "), 4)
    zr_buf_str(b, RClass.name(recv))
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_ivtab_get(ClassExt.cv(RClass.ext(owner)), id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_variable_set(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_cvar_name(id)
  return r if r == QUNDEF
  owner = zr_cvar_owner(recv, id)
  if owner == QNIL
    owner = recv
  end
  v = Machine.value(Machine.load64(argv, 8))
  zr_ivtab_set(ClassExt.cv(RClass.ext(owner)), id, v)
  v
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_variable_defined(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_cvar_name(id)
  return r if r == QUNDEF
  zr_bool(zr_cvar_owner(recv, id) != QNIL)
end

# `Object#singleton_methods`: the singleton class's own public and
# protected methods, and with `all` those of the modules it extends
# and, for a class, of its superclasses' singleton classes.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_singleton_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  out = zr_ary_new(4)
  seen = zr_ary_new(4)
  if zr_special_p(recv)
    return out
  end
  k = zr_class_of(recv)
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

# `methods`, and the three by visibility; `methods(false)` is
# `singleton_methods(false)`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_methods(recv, argc, argv, cref, blk)
  if argc == 1 && (Machine.value(Machine.load64(argv, 0)) == QFALSE || Machine.value(Machine.load64(argv, 0)) == QNIL)
    return zr_obj_singleton_methods(recv, argc, argv, cref, blk)
  end
  zr_method_names(zr_class_of(recv), 1, 0 - 1, true)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_public_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PUBLIC, true)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_private_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PRIVATE, true)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_protected_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(zr_class_of(recv), all ? 1 : 0, VIS_PROTECTED, true)
end

# `method_defined?` and the three by visibility: whether the module or
# an ancestor answers the name with that visibility.
sig [Value, Word, Ptr, Word] => Value
machine def zr_mod_method_defined_vis(recv, argc, argv, vis)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  inherit = argc < 2 || (Machine.value(Machine.load64(argv, 8)) != QFALSE && Machine.value(Machine.load64(argv, 8)) != QNIL)
  e = inherit ? zr_find_method(recv, Machine.load64(slot, 0)) : zr_find_method_at(recv, Machine.load64(slot, 0))
  if e == 0 || MEntry.kind(e) == KIND_UNDEF
    return Machine.value(QFALSE)
  end
  zr_bool(vis < 0 ? MEntry.vis(e) != VIS_PRIVATE : MEntry.vis(e) == vis)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_method_defined(recv, argc, argv, cref, blk)
  zr_mod_method_defined_vis(recv, argc, argv, 0 - 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_method_defined(recv, argc, argv, cref, blk)
  zr_mod_method_defined_vis(recv, argc, argv, VIS_PUBLIC)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_method_defined(recv, argc, argv, cref, blk)
  zr_mod_method_defined_vis(recv, argc, argv, VIS_PRIVATE)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_protected_method_defined(recv, argc, argv, cref, blk)
  zr_mod_method_defined_vis(recv, argc, argv, VIS_PROTECTED)
end

# `Method#super_method`: the method past this one's owner in the
# receiver's chain, bound the same way, or nil.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_super_method(recv, argc, argv, cref, blk)
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

# `Module#included_modules`: the modules in the chain, nearest first.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_included_modules(recv, argc, argv, cref, blk)
  out = zr_ary_new(8)
  k = RClass.superclass(recv)
  while k != QNIL
    if zr_type(k) == T_ICLASS && RClass.origin(k) == QNIL && zr_type(RClass.attached(k)) == T_MODULE
      zr_ary_push(out, RClass.attached(k))
    end
    k = RClass.superclass(k)
  end
  out
end

# `Module.nesting`: the classes and modules whose bodies enclose the
# caller, innermost first; an eval's cref is not lexical and is skipped.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_nesting(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  c = Frame.cref(Frame.prev(Task.top(zr_task())))
  while c != QNIL && c != zr_global(G_TOP_CREF)
    if RCref.eval(c) == 0
      zr_ary_push(out, RCref.klass(c))
    end
    c = RCref.next(c)
  end
  out
end

# `__method__`: the name of the method the caller is in, through any
# blocks, or nil at the top level or in a class body.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_method_name(recv, argc, argv, cref, blk)
  meta = Frame.meta(Frame.prev(Task.top(zr_task())))
  while FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN
    meta = FrameMeta.parent(meta)
  end
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BMETHOD
    return Machine.value(QNIL)
  end
  zr_sym(FrameMeta.name(meta))
end

# `Proc#source_location`: where the block was written, or nil for one
# the runtime made.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_source_location(recv, argc, argv, cref, blk)
  meta = RProc.meta(recv)
  if meta == 0 || FrameMeta.file_len(meta) == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta)))
  zr_ary_push(out, zr_fix(FrameMeta.line(meta)))
  out
end

# The main object's own verbs: `include`, `public` and `private` act
# on Object.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_include(recv, argc, argv, cref, blk)
  zr_mod_include(zr_global(G_OBJECT), argc, argv, cref, blk)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_public(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PUBLIC, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_private(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PRIVATE, 0)
end
