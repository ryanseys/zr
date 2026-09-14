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
    s = zr_inspect(name)
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

# An identifier: a letter, underscore or byte past ASCII, then those
# and digits.
sig [Ptr, Word] => Bool
machine def zr_ident_p(p, n)
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
machine def zr_check_ivar_name(id)
  zr_bad_variable_name(id, Machine.bytes("@"), 1, Machine.bytes("an instance"), 11)
end

sig [Word] => Value
machine def zr_check_cvar_name(id)
  zr_bad_variable_name(id, Machine.bytes("@@"), 2, Machine.bytes("a class"), 7)
end

# The names in a variable table, as Symbols, each once, after those
# already in `out`. `lead` is the byte a name of this kind starts with,
# which is what tells a hidden name of the lowering from a real one.
sig [Ptr, Value, Word] => Void
machine def zr_ivtab_names(t, out, lead)
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
machine def zr_obj_instance_variables(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  t = zr_ivtab(recv)
  if t != 0
    zr_ivtab_names(t, out, 64)
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
  r = zr_ractor_guard(recv)
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
  r = zr_ractor_guard(recv)
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
    zr_buf_class(b, recv)
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
  r = zr_class_modify_check(owner)
  return r if r == QUNDEF
  v = Machine.value(Machine.load64(argv, 8))
  zr_ivtab_set(ClassExt.cv(RClass.ext(owner)), id, v)
  v
end

# `Module#remove_class_variable`: the row leaves the owning module's
# table, and its value is the answer.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_remove_class_variable(recv, argc, argv, cref, blk)
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
    zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
    zr_exc_detail(exc, Machine.id(:@receiver), recv)
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
  if e == 0 || MEntry.kind(e) == KIND_UNDEF || zr_entry_hidden_p(e)
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
    if zr_type(k) == T_ICLASS && RClass.origin(k) == QNIL && k != RClass.origin(recv) && zr_type(RClass.attached(k)) == T_MODULE
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
      zr_ary_push(out, zr_cref_klass(c))
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
  while (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.kind(meta) == KIND_EVAL) && FrameMeta.parent(meta) != 0
    meta = FrameMeta.parent(meta)
  end
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BMETHOD
    return Machine.value(QNIL)
  end
  zr_sym(FrameMeta.name(meta))
end

# `__callee__`: the name the method was called by, an alias's own.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_callee(recv, argc, argv, cref, blk)
  rec = Frame.prev(Task.top(zr_task()))
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
  # A method the runtime writes in Ruby runs as a builtin, and is called
  # by an alias as much as a program's own is.
  if FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BMETHOD && FrameMeta.kind(meta) != KIND_BUILTIN
    return Machine.value(QNIL)
  end
  if Frame.mid(rec) == 0
    return zr_sym(FrameMeta.name(meta))
  end
  zr_sym(Frame.mid(rec))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_singleton_class_p(recv, argc, argv, cref, blk)
  zr_bool(zr_singleton_p(recv))
end

# `Proc#source_location`: where the block was written, or nil for one
# the runtime made.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_source_location(recv, argc, argv, cref, blk)
  # A Method's Proc is where the method is.
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

# The main object's own verbs: `include`, `public` and `private` act
# on Object.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_include(recv, argc, argv, cref, blk)
  zr_send(zr_global(G_OBJECT), Machine.id(:include), argc, argv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_public(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PUBLIC, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_private(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_global(G_OBJECT), argc, argv, blk, VIS_PRIVATE, 0)
end

# `Module#remove_method`: the entry must be the module's own.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_remove_method(recv, argc, argv, cref, blk)
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
      zr_exc_detail(exc, Machine.id(:@name), zr_sym(mid))
      zr_exc_detail(exc, Machine.id(:@receiver), recv)
      return zr_raise(exc)
    end
    ext = RClass.ext(klass)
    zr_save_core_row(ext, e)
    last = ClassExt.mtab(ext) + ((ClassExt.mlen(ext) - 1) * MEntry.size)
    if e != last
      zr_memmove(e, e + MEntry.size, last - e)
    end
    ClassExt.set_mlen(ext, ClassExt.mlen(ext) - 1)
    zr_methods_changed()
    zr_gates_recheck(mid)
    r = zr_method_removed(recv, mid)
    return r if r == QUNDEF
    i += 1
  end
  recv
end

# The `method_removed` or `singleton_method_removed` hook, when the
# program defines one.
sig [Value, Word] => Value
machine def zr_method_removed(klass, mid)
  zr_method_hook(klass, mid, Machine.id(:method_removed), Machine.id(:singleton_method_removed))
end

sig [Value, Word] => Value
machine def zr_method_undefined(klass, mid)
  zr_method_hook(klass, mid, Machine.id(:method_undefined), Machine.id(:singleton_method_undefined))
end

# `hook` on the class, or `singleton_hook` on what a singleton class
# is attached to, when the program defines one.
sig [Value, Word, Word, Word] => Value
machine def zr_method_hook(klass, mid, hook, singleton_hook)
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

# `remove_instance_variable(name)`: the value, and the row is gone.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_remove_instance_variable(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  r = zr_check_ivar_name(id)
  return r if r == QUNDEF
  if zr_frozen_p(recv)
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
    zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
    zr_exc_detail(exc, Machine.id(:@receiver), recv)
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

# `Class#subclasses`: the classes whose superclass is this one, newest
# first, singleton classes left out; read off the arena and ordered by
# creation serial.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_subclasses(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    i = 0
    while i < CELLS
      cell = base + (i * CELL)
      flags = Machine.load64(cell, 0)
      if (flags & FL_ALLOCATED) != 0 && (flags & T_MASK) == T_CLASS && (flags & FL_SINGLETON) == 0
        k = Machine.value(cell)
        if k != recv && zr_real_superclass(k) == recv
          zr_ary_insert_by_serial(out, k)
        end
      end
      i += 1
    end
    a += 1
  end
  out
end

# `k` placed before the first class made earlier than it.
sig [Value, Value] => Void
machine def zr_ary_insert_by_serial(out, k)
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
machine def zr_main_define_method(recv, argc, argv, cref, blk)
  zr_mod_define_method(zr_global(G_OBJECT), argc, argv, cref, blk)
end

# The main object's `to_s` and `inspect`: `main`, as its own singleton
# methods.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_main_to_s(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("main"), 4)
end

# `attached_object`: the object a singleton class belongs to; a plain
# class has none.
sig [Value] => Value
machine def zr_mod_attached(klass)
  if !zr_singleton_p(klass)
    return Machine.value(QNIL)
  end
  RClass.attached(klass)
end
