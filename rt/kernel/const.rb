# Constants and the lexical class chain. A cref cell names a class and
# the cref outside it; the toplevel's is Object alone. A constant read
# looks through the lexical chain (Object last, and only as an
# ancestor), then the innermost class's ancestors.
Machine.struct :RCref, basic: RBasic, klass: Value, next: Value
T_CREF = 25
G_TOP_CREF = 24

sig [Value, Value] => Value
machine def zr_cref_push(klass, outer)
  c = zr_alloc(T_CREF, Machine.value(QNIL))
  RCref.set_klass(c, klass)
  RCref.set_next(c, outer)
  c
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
    ClassExt.set_clen(ext, n + 1)
  end
  CEntry.set_value(e, v)
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
  zr_raise_buf(zr_global(G_NAME_ERROR), b)
end

# A bare constant under `cref`: the lexical scopes, then the innermost
# scope's ancestors, then Object when that scope is a module.
sig [Value, Word] => Value
machine def zr_const_get(cref, id)
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
  if e == 0
    return Machine.value(QUNDEF)
  end
  CEntry.value(e)
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
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if sup != QUNDEF && RClass.superclass(k) != sup
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
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("superclass must be an instance of Class (given an instance of "), 62)
  end
  k = zr_class_new(sup)
  RClass.set_name(k, zr_class_name_under(scope, id))
  zr_const_set(scope, id, k)
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
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    return m
  end
  m = zr_module_new()
  RClass.set_name(m, zr_class_name_under(scope, id))
  zr_const_set(scope, id, m)
  m
end
