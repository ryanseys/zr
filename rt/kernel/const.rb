# Constants and the lexical class chain. A cref cell names a class and
# the cref outside it; the toplevel's is Object alone. A constant read
# looks through the lexical chain (Object last, and only as an
# ancestor), then the innermost class's ancestors.
# `vis` is the visibility a def under the cref gets (VIS_*), and
# `modfn` whether `module_function` is on.
# A cref pushed by `class_eval`, `instance_eval` or `Class.new` (`eval`
# set) is where a `def` lands, but constants and class variables look
# through it to the lexical scope. The cref of a method `define_method`
# made names its entry, which `super` in the body resolves from.
Machine.struct :RCref, basic: RBasic, klass: Value, next: Value, vis: Word, modfn: Word, eval: Word, entry: Ptr
T_CREF = 25
VIS_PUBLIC = 0
VIS_PRIVATE = 1
VIS_PROTECTED = 2
G_TOP_CREF = 24

sig [Value, Value] => Value
machine def zr_cref_push(klass, outer)
  c = zr_alloc(T_CREF, Machine.value(QNIL))
  RCref.set_klass(c, klass)
  RCref.set_next(c, outer)
  RCref.set_vis(c, VIS_PUBLIC)
  RCref.set_modfn(c, 0)
  RCref.set_eval(c, 0)
  RCref.set_entry(c, 0)
  c
end

sig [Value, Value] => Value
machine def zr_cref_push_eval(klass, outer)
  c = zr_cref_push(klass, outer)
  RCref.set_eval(c, 1)
  c
end

# The innermost cref that names a lexical scope.
sig [Value] => Value
machine def zr_cref_lexical(cref)
  while RCref.eval(cref) != 0
    cref = RCref.next(cref)
  end
  cref
end

sig [Value] => Value
machine def zr_cref_lexical_class(cref)
  RCref.klass(zr_cref_lexical(cref))
end

# The constant row for `id` on `klass` alone, or 0.
sig [Value, Word] => Ptr
machine def zr_const_row(klass, id)
  ext = RClass.ext(klass)
  n = ClassExt.clen(ext)
  i = 0
  while i < n
    e = ClassExt.ctab(ext) + (i * CEntry.size)
    if CEntry.id(e) == id
      return e
    end
    i += 1
  end
  0
end

# A constant stored under `klass`; an anonymous class or module takes
# the constant's name.
sig [Value, Word, Value] => Void
machine def zr_const_set(klass, id, v)
  e = zr_const_row(klass, id)
  if e == 0
    ext = RClass.ext(klass)
    n = ClassExt.clen(ext)
    if n == ClassExt.ccap(ext)
      cap = n * 2
      if cap < 8
        cap = 8
      end
      tab = malloc(cap * CEntry.size)
      if ClassExt.ctab(ext) != 0
        zr_memcpy(tab, ClassExt.ctab(ext), n * CEntry.size)
        free(ClassExt.ctab(ext))
      end
      ClassExt.set_ctab(ext, tab)
      ClassExt.set_ccap(ext, cap)
    end
    e = ClassExt.ctab(ext) + (n * CEntry.size)
    CEntry.set_id(e, id)
    CEntry.set_private(e, 0)
    ClassExt.set_clen(ext, n + 1)
  end
  CEntry.set_value(e, v)
  if !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) && RClass.name(v) == QNIL
    RClass.set_name(v, zr_class_name_under(klass, id))
  end
  top = Task.top(zr_task())
  if top == 0
    CEntry.set_file(e, 0)
    CEntry.set_file_len(e, 0)
    CEntry.set_line(e, 0)
  else
    CEntry.set_file(e, FrameMeta.file(Frame.meta(top)))
    CEntry.set_file_len(e, FrameMeta.file_len(Frame.meta(top)))
    CEntry.set_line(e, Frame.line(top))
  end
end

# `\nfile:line: previous definition of Name was here` after a message
# about a constant; one the runtime set has no file and no line, and
# CRuby prints them empty.
sig [Ptr, Ptr, Word] => Void
machine def zr_buf_previous_definition(b, e, id)
  zr_buf_byte(b, 10)
  zr_buf_push(b, CEntry.file(e), CEntry.file_len(e))
  zr_buf_byte(b, 58)
  if CEntry.file_len(e) > 0
    zr_buf_long(b, CEntry.line(e))
  end
  zr_buf_push(b, Machine.bytes(": previous definition of "), 25)
  zr_buf_sym(b, id)
  zr_buf_push(b, Machine.bytes(" was here"), 9)
end

# The row for `id` on `klass` or an ancestor, or 0; `skip_object` leaves
# Object's own constants out, as `A::X` does.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_in(klass, id, skip_object)
  while klass != QNIL
    unless skip_object && klass == zr_global(G_OBJECT)
      e = zr_const_row(klass, id)
      if e != 0
        return e
      end
    end
    klass = RClass.superclass(klass)
  end
  0
end

sig [Value, Word] => Value
machine def zr_uninitialized_constant(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("uninitialized constant "), 23)
  if scope != QNIL && scope != zr_global(G_OBJECT)
    zr_buf_str(b, RClass.name(scope))
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  e = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:@name), zr_sym(id))
  zr_exc_detail(e, Machine.id(:@receiver), scope == QNIL ? zr_global(G_OBJECT) : scope)
  zr_raise(e)
end

# A bare constant under `cref`: the lexical scopes, then the innermost
# scope's ancestors, then Object when that scope is a module.
sig [Value, Word] => Value
machine def zr_const_get(cref, id)
  cref = zr_cref_lexical(cref)
  c = cref
  while RCref.next(c) != QNIL
    e = zr_const_row(RCref.klass(c), id)
    if e != 0
      return CEntry.value(e)
    end
    c = RCref.next(c)
  end
  e = zr_const_row_in(RCref.klass(cref), id, false)
  if e == 0 && zr_type(RCref.klass(cref)) == T_MODULE
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e == 0
    return zr_uninitialized_constant(RCref.klass(cref), id)
  end
  CEntry.value(e)
end

# A bare constant under `cref` for `defined?` and `||=`: the value, or
# undef with nothing raised.
sig [Value, Word] => Value
machine def zr_const_lookup(cref, id)
  cref = zr_cref_lexical(cref)
  c = cref
  while RCref.next(c) != QNIL
    e = zr_const_row(RCref.klass(c), id)
    if e != 0
      return CEntry.value(e)
    end
    c = RCref.next(c)
  end
  e = zr_const_row_in(RCref.klass(cref), id, false)
  if e == 0 && zr_type(RCref.klass(cref)) == T_MODULE
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e == 0
    return Machine.value(QUNDEF)
  end
  CEntry.value(e)
end

sig [Value, Word] => Value
machine def zr_const_lookup_at(scope, id)
  if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
    return Machine.value(QUNDEF)
  end
  e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
  if e == 0 || CEntry.private(e) != 0
    return Machine.value(QUNDEF)
  end
  CEntry.value(e)
end

# `private constant Foo::BAR referenced`.
sig [Value, Word] => Value
machine def zr_private_constant(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("private constant "), 17)
  if scope != zr_global(G_OBJECT)
    zr_buf_str(b, zr_class_to_s(scope, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  zr_buf_push(b, Machine.bytes(" referenced"), 11)
  exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
  zr_exc_detail(exc, Machine.id(:@receiver), scope)
  zr_raise(exc)
end

# `private_constant(*names)` and `public_constant(*names)`: the flag on
# the module's own rows.
sig [Value, Word, Ptr, Word] => Value
machine def zr_mod_constant_visibility(recv, argc, argv, private)
  i = 0
  while i < argc
    slot = Machine.slot(8)
    r = zr_const_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    e = zr_const_row(recv, id)
    if e == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("constant "), 9)
      zr_buf_str(b, zr_class_to_s(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
      zr_buf_push(b, Machine.bytes("::"), 2)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" not defined"), 12)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
      zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:@receiver), recv)
      return zr_raise(exc)
    end
    CEntry.set_private(e, private)
    i += 1
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_constant(recv, argc, argv, cref, blk)
  zr_mod_constant_visibility(recv, argc, argv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_constant(recv, argc, argv, cref, blk)
  zr_mod_constant_visibility(recv, argc, argv, 0)
end

# `scope::Name`.
sig [Value, Word] => Value
machine def zr_const_get_at(scope, id)
  if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    s = zr_send(scope, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    zr_buf_push(b, Machine.bytes(" is not a class/module"), 22)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
  if e == 0
    return zr_uninitialized_constant(scope, id)
  end
  if CEntry.private(e) != 0
    return zr_private_constant(scope, id)
  end
  CEntry.value(e)
end

# The name a class gets under `scope`: `Outer::Name` unless the scope
# is Object.
sig [Value, Word] => Value
machine def zr_class_name_under(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if scope != zr_global(G_OBJECT) && RClass.name(scope) != QNIL
    zr_buf_str(b, RClass.name(scope))
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  zr_buf_take(b)
end

# `class Name < sup` under `scope`: the class the constant names when it
# exists (and its superclass agrees), else a new one. `sup` is undef
# when the program wrote no superclass.
sig [Value, Word, Value] => Value
machine def zr_class_define(scope, id, sup)
  e = zr_const_row(scope, id)
  if e == 0 && scope == zr_global(G_OBJECT)
    e = zr_const_row_in(scope, id, false)
  end
  if e != 0
    k = CEntry.value(e)
    if zr_special_p(k) || zr_type(k) != T_CLASS
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" is not a class"), 15)
      zr_buf_previous_definition(b, e, id)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if sup != QUNDEF && zr_real_superclass(k) != sup
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("superclass mismatch for class "), 30)
      zr_buf_sym(b, id)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    return k
  end
  if sup == QUNDEF
    sup = zr_global(G_OBJECT)
  elsif zr_special_p(sup) || zr_type(sup) != T_CLASS
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("superclass must be an instance of Class (given an instance of "), 62)
    zr_buf_str(b, zr_class_name_of(sup))
    zr_buf_byte(b, 41)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  k = zr_class_new(sup)
  RClass.set_name(k, zr_class_name_under(scope, id))
  zr_const_set(scope, id, k)
  r = zr_hook(sup, Machine.id(:inherited), k)
  return r if r == QUNDEF
  k
end

sig [Value, Word] => Value
machine def zr_module_define(scope, id)
  e = zr_const_row(scope, id)
  if e == 0 && scope == zr_global(G_OBJECT)
    e = zr_const_row_in(scope, id, false)
  end
  if e != 0
    m = CEntry.value(e)
    if zr_special_p(m) || zr_type(m) != T_MODULE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" is not a module"), 16)
      zr_buf_previous_definition(b, e, id)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    return m
  end
  m = zr_module_new()
  RClass.set_name(m, zr_class_name_under(scope, id))
  zr_const_set(scope, id, m)
  m
end

# A constant's name given as a Symbol or String, as its id in `out`;
# `wrong constant name x` otherwise.
sig [Value, Ptr] => Value
machine def zr_const_name_id(name, out)
  r = zr_name_id(name, out)
  return r if r == QUNDEF
  id = Machine.load64(out, 0)
  c = Machine.word(Machine.load8(zr_symbol_name_ptr(id), 0))
  if c < 65 || c > 90
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong constant name "), 20)
    zr_buf_sym(b, id)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  Machine.value(QNIL)
end

# Whether the second argument, when given, is not false or nil.
sig [Word, Ptr] => Bool
machine def zr_inherit_flag(argc, argv)
  if argc < 2
    return true
  end
  v = Machine.value(Machine.load64(argv, 8))
  v != QFALSE && v != QNIL
end

# The row `const_get` and `const_defined?` find: the module's own, its
# ancestors' when `inherit`, and Object's for a module either way.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_for(mod, id, inherit)
  if inherit
    e = zr_const_row_in(mod, id, false)
    if e == 0 && zr_type(mod) == T_MODULE
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    return e
  end
  zr_const_row(mod, id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_const_get(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_const_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  e = zr_const_row_for(recv, id, zr_inherit_flag(argc, argv))
  if e == 0
    return zr_uninitialized_constant(recv, id)
  end
  CEntry.value(e)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_const_defined(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_const_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_bool(zr_const_row_for(recv, Machine.load64(slot, 0), zr_inherit_flag(argc, argv)) != 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_const_set(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_const_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  v = Machine.value(Machine.load64(argv, 8))
  zr_const_set(recv, Machine.load64(slot, 0), v)
  v
end

# `constants`: the module's own names, then its ancestors' but
# Object's, each once.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_constants(recv, argc, argv, cref, blk)
  inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  out = zr_ary_new(8)
  k = recv
  while k != QNIL
    if k != zr_global(G_OBJECT) || recv == zr_global(G_OBJECT)
      ext = RClass.ext(k)
      i = 0
      while i < ClassExt.clen(ext)
        e = ClassExt.ctab(ext) + (i * CEntry.size)
        name = zr_sym(CEntry.id(e))
        if CEntry.private(e) == 0 && zr_ary_index_of(out, name) < 0
          zr_ary_push(out, name)
        end
        i += 1
      end
    end
    if inherit
      k = RClass.superclass(k)
    else
      k = Machine.value(QNIL)
    end
  end
  out
end
