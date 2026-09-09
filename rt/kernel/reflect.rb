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
# already in `out`.
sig [Ptr, Value] => Void
machine def zr_ivtab_names(t, out)
  i = 0
  while i < IvTab.len(t)
    name = zr_sym(IvEntry.id(IvTab.rows(t) + (i * IvEntry.size)))
    if zr_ary_index_of(out, name) < 0
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
# protected methods, and with `all` those of the modules it extends.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_singleton_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  out = zr_ary_new(4)
  if zr_special_p(recv)
    return out
  end
  k = zr_class_of(recv)
  if !zr_singleton_p(k)
    return out
  end
  zr_level_method_names(k, k, out, 0 - 1)
  if all
    k = RClass.superclass(k)
    while k != QNIL && zr_type(k) == T_ICLASS
      zr_level_method_names(k, k, out, 0 - 1)
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
