# Classes and modules: a name, a superclass, and an extension outside
# the arena holding the method table (id, code, arity, kind, meta,
# cref rows searched in order) and the constant table (id, value rows).
# Method code takes `(recv, argc, argv, cref)` and answers a Value; the
# cref is the lexical class chain the method was defined under.
Machine.struct :RClass, basic: RBasic, name: Value, superclass: Value, ext: Ptr
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value
Machine.struct :CEntry, id: Word, value: Value
Machine.sig :method, [Value, Word, Ptr, Value] => Value
# Method kinds beyond a compiled def and a builtin: accessors keep the
# ivar's id in `fn`.
KIND_ATTR_READER = 3
KIND_ATTR_WRITER = 4

sig [Word, Value, Value] => Value
machine def zr_class_alloc(type, sup, klass)
  c = zr_alloc(type, klass)
  RClass.set_name(c, Machine.value(QNIL))
  RClass.set_superclass(c, sup)
  ext = malloc(ClassExt.size)
  ClassExt.set_mtab(ext, 0)
  ClassExt.set_mlen(ext, 0)
  ClassExt.set_mcap(ext, 0)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  RClass.set_ext(c, ext)
  c
end

sig [Value] => Value
machine def zr_class_new(sup)
  zr_class_alloc(T_CLASS, sup, zr_global(G_CLASS))
end

sig [] => Value
machine def zr_module_new
  zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_MODULE))
end

# The gate bit an operator's redefinition sets, or 0.
sig [Value, Word] => Word
machine def zr_gate_bit(klass, mid)
  if klass == zr_global(G_INTEGER)
    if mid == Machine.id(:+)
      GATE_PLUS
    elsif mid == Machine.id(:-)
      GATE_MINUS
    elsif mid == Machine.id(:*)
      GATE_MUL
    elsif mid == Machine.id(:/)
      GATE_DIV
    elsif mid == Machine.id(:%)
      GATE_MOD
    elsif mid == Machine.id(:<)
      GATE_LT
    elsif mid == Machine.id(:<=)
      GATE_LE
    elsif mid == Machine.id(:>)
      GATE_GT
    elsif mid == Machine.id(:>=)
      GATE_GE
    elsif mid == Machine.id(:==)
      GATE_EQ
    elsif mid == Machine.id(:!=)
      GATE_NE
    else
      0
    end
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
    GATE_AREF
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
    GATE_ASET
  elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
    GATE_LTLT
  elsif mid == Machine.id(:!)
    GATE_NOT
  else
    0
  end
end

# A definition; the first one of each builtin operator is the runtime's
# own and leaves the gate clear, a later one sets it. `meta` is the
# compiled def's own FrameMeta, or 0 for a builtin, which gets one here.
sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Void
machine def zr_define_method(klass, mid, fn, arity, kind, meta, cref)
  if meta == 0
    meta = malloc(FrameMeta.size)
    FrameMeta.set_file(meta, 0)
    FrameMeta.set_file_len(meta, 0)
    FrameMeta.set_kind(meta, KIND_BUILTIN)
    FrameMeta.set_line(meta, 0)
  end
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  if zr_find_method(klass, mid) != 0
    g = zr_gates()
    Machine.store64(g, 0, Machine.load64(g, 0) | zr_gate_bit(klass, mid))
  end
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  if n == ClassExt.mcap(ext)
    cap = n * 2
    if cap < 8
      cap = 8
    end
    tab = malloc(cap * MEntry.size)
    old = ClassExt.mtab(ext)
    if old != 0
      zr_memcpy(tab, old, n * MEntry.size)
      free(old)
    end
    ClassExt.set_mtab(ext, tab)
    ClassExt.set_mcap(ext, cap)
  end
  e = ClassExt.mtab(ext) + (n * MEntry.size)
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  MEntry.set_cref(e, cref)
  ClassExt.set_mlen(ext, n + 1)
end

sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin(klass, mid, fn, arity)
  zr_define_method(klass, mid, fn, arity, KIND_BUILTIN, 0, Machine.value(QNIL))
end

# The entry for `mid` on `klass` alone, or 0; the last definition wins.
sig [Value, Word] => Ptr
machine def zr_find_method_at(klass, mid)
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  tab = ClassExt.mtab(ext)
  i = n - 1
  while i >= 0
    e = tab + (i * MEntry.size)
    if MEntry.mid(e) == mid
      return e
    end
    i -= 1
  end
  0
end

# The entry for `mid` on `klass` or an ancestor, or 0.
sig [Value, Word] => Ptr
machine def zr_find_method(klass, mid)
  while klass != QNIL
    e = zr_find_method_at(klass, mid)
    if e != 0
      return e
    end
    klass = RClass.superclass(klass)
  end
  0
end

sig [Value] => Value
machine def zr_class_of(v)
  if zr_fixnum_p(v)
    zr_global(G_INTEGER)
  elsif v == QNIL
    zr_global(G_NIL)
  elsif v == QTRUE
    zr_global(G_TRUE)
  elsif v == QFALSE
    zr_global(G_FALSE)
  elsif zr_symbol_p(v)
    zr_global(G_SYMBOL)
  else
    RBasic.klass(v)
  end
end

# Whether `klass` is `target` or inherits from it.
sig [Value, Value] => Bool
machine def zr_class_inherits(klass, target)
  while klass != QNIL
    if klass == target
      return true
    end
    klass = RClass.superclass(klass)
  end
  false
end

sig [Value, Value] => Bool
machine def zr_is_a(v, klass)
  zr_class_inherits(zr_class_of(v), klass)
end

# What a cell holds besides its class: marked by type.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_CLASS || t == T_MODULE
    zr_mark(RClass.name(v))
    zr_mark(RClass.superclass(v))
    ext = RClass.ext(v)
    n = ClassExt.mlen(ext)
    i = 0
    while i < n
      zr_mark(MEntry.cref(ClassExt.mtab(ext) + (i * MEntry.size)))
      i += 1
    end
    n = ClassExt.clen(ext)
    i = 0
    while i < n
      zr_mark(CEntry.value(ClassExt.ctab(ext) + (i * CEntry.size)))
      i += 1
    end
  elsif t == T_EXCEPTION
    zr_mark(RException.message(v))
  elsif t == T_OBJECT
    zr_mark_ivars(v)
  elsif t == T_ARRAY
    zr_mark_ary(v)
  elsif t == T_CREF
    zr_mark(RCref.klass(v))
    zr_mark(RCref.next(v))
  end
end

# What a cell owns outside the arena: freed with it.
sig [Value] => Void
machine def zr_release(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_CLASS || t == T_MODULE
    ext = RClass.ext(v)
    if ClassExt.mtab(ext) != 0
      free(ClassExt.mtab(ext))
    end
    if ClassExt.ctab(ext) != 0
      free(ClassExt.ctab(ext))
    end
    free(ext)
  elsif t == T_STRING
    if RString.ptr(v) != 0
      free(RString.ptr(v))
    end
  elsif t == T_EXCEPTION
    if RException.rows(v) != 0
      free(RException.rows(v))
    end
  elsif t == T_OBJECT
    if RObject.ivars(v) != 0
      free(RObject.ivars(v))
    end
  elsif t == T_ARRAY
    free(RArray.ptr(v))
  end
end
