# Classes and modules: a name, a superclass, and an extension outside
# the arena holding the method table (id, code, arity, kind, meta,
# cref rows searched in order) and the constant table (id, value rows).
# An included module sits in the superclass chain as a proxy (T_ICLASS)
# that shares the module's extension and names it as `attached`.
# Method code takes `(recv, argc, argv, cref)` and answers a Value; the
# cref is the lexical class chain the method was defined under.
Machine.struct :RClass, basic: RBasic, name: Value, superclass: Value, ext: Ptr, attached: Value
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word, iv: IvTab
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value
Machine.struct :CEntry, id: Word, value: Value
Machine.sig :method, [Value, Word, Ptr, Value, Value] => Value
# Method kinds beyond a compiled def and a builtin: accessors keep the
# ivar's id in `fn`.
KIND_ATTR_READER = 3
KIND_ATTR_WRITER = 4
# A builtin that leaves no frame of its own: `Proc#call`, which CRuby
# keeps out of a backtrace.
KIND_FRAMELESS = 5

sig [Word, Value, Value] => Value
machine def zr_class_alloc(type, sup, klass)
  c = zr_alloc(type, klass)
  RClass.set_name(c, Machine.value(QNIL))
  RClass.set_superclass(c, sup)
  RClass.set_attached(c, Machine.value(QNIL))
  ext = malloc(ClassExt.size)
  ClassExt.set_mtab(ext, 0)
  ClassExt.set_mlen(ext, 0)
  ClassExt.set_mcap(ext, 0)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  zr_ivtab_init(ClassExt.iv(ext))
  RClass.set_ext(c, ext)
  c
end

# A class without a metaclass yet: a builtin class gets one on first
# use, the way `zr_singleton_class` makes any.
sig [Value] => Value
machine def zr_class_boot(sup)
  zr_class_alloc(T_CLASS, sup, zr_global(G_CLASS))
end

# A class with its metaclass, as CRuby makes every class: the metaclass
# inherits from the superclass's, so class methods do too.
sig [Value] => Value
machine def zr_class_new(sup)
  c = zr_class_boot(sup)
  zr_make_metaclass(c)
  c
end

T_ICLASS = 28

# Whether `klass`'s chain holds `mod`, itself or as a proxy.
sig [Value, Value] => Bool
machine def zr_chain_includes(klass, mod)
  k = klass
  while k != QNIL
    if k == mod || (zr_type(k) == T_ICLASS && RClass.attached(k) == mod)
      return true
    end
    k = RClass.superclass(k)
  end
  false
end

# `include`: a proxy for `mod`, and for each module it includes, goes
# in right after `klass`, unless the chain holds it already.
sig [Value, Value] => Void
machine def zr_include_module(klass, mod)
  c = klass
  m = mod
  while m != QNIL
    origin = zr_type(m) == T_ICLASS ? RClass.attached(m) : m
    unless zr_chain_includes(klass, origin)
      ic = zr_alloc(T_ICLASS, origin)
      RClass.set_name(ic, Machine.value(QNIL))
      RClass.set_superclass(ic, RClass.superclass(c))
      RClass.set_ext(ic, RClass.ext(origin))
      RClass.set_attached(ic, origin)
      RClass.set_superclass(c, ic)
      c = ic
    end
    m = RClass.superclass(m)
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_include(recv, argc, argv, cref, blk)
  i = argc - 1
  while i >= 0
    m = Machine.value(Machine.load64(argv + (i * 8), 0))
    if zr_special_p(m) || zr_type(m) != T_MODULE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_str(b, zr_class_name_of(m))
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    zr_include_module(recv, m)
    i -= 1
  end
  recv
end

# `Module#include?`: `mod` is in the chain, other than as itself.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_include_p(recv, argc, argv, cref, blk)
  m = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(m) || zr_type(m) != T_MODULE
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("wrong argument type Class (expected Module)"), 43)
  end
  zr_bool(m != recv && zr_chain_includes(recv, m))
end

sig [Value] => Bool
machine def zr_singleton_p(klass)
  (RBasic.flags(klass) & FL_SINGLETON) != 0
end

# The singleton class of the class `klass`: its superclass's, or Class
# for a root; `klass` itself has it as its class from here on.
sig [Value] => Value
machine def zr_make_metaclass(klass)
  sup = RClass.superclass(klass)
  if sup == QNIL
    msup = zr_global(G_CLASS)
  else
    msup = zr_singleton_class(sup)
  end
  meta = zr_class_alloc(T_CLASS, msup, zr_global(G_CLASS))
  RBasic.set_flags(meta, RBasic.flags(meta) | FL_SINGLETON)
  RClass.set_attached(meta, klass)
  RBasic.set_klass(klass, meta)
  meta
end

# The singleton class of `v`, made on first use. An Integer or a Symbol
# has none; nil, true and false answer their own class.
sig [Value] => Value
machine def zr_singleton_class(v)
  if zr_fixnum_p(v) || zr_symbol_p(v)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  if zr_special_p(v)
    return zr_class_of(v)
  end
  k = RBasic.klass(v)
  if zr_singleton_p(k) && RClass.attached(k) == v
    return k
  end
  if zr_type(v) == T_CLASS
    return zr_make_metaclass(v)
  end
  s = zr_class_alloc(T_CLASS, k, zr_global(G_CLASS))
  RBasic.set_flags(s, RBasic.flags(s) | FL_SINGLETON)
  RClass.set_attached(s, v)
  RBasic.set_klass(v, s)
  s
end

# The class `v.class` answers: past any singleton class.
sig [Value] => Value
machine def zr_real_class(v)
  k = zr_class_of(v)
  while zr_singleton_p(k)
    k = RClass.superclass(k)
  end
  k
end

sig [Value] => Value
machine def zr_class_name_of(v)
  RClass.name(zr_real_class(v))
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
    FrameMeta.set_parent(meta, 0)
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

# Whether `klass` is `target` or inherits from it, or includes it.
sig [Value, Value] => Bool
machine def zr_class_inherits(klass, target)
  zr_chain_includes(klass, target)
end

sig [Value, Value] => Bool
machine def zr_is_a(v, klass)
  zr_class_inherits(zr_class_of(v), klass)
end

# What a cell holds besides its class: marked by type.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_ICLASS
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
  elsif t == T_CLASS || t == T_MODULE
    zr_mark(RClass.name(v))
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
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
    zr_mark_ivtab(ClassExt.iv(ext))
  elsif t == T_EXCEPTION
    zr_mark(RException.message(v))
  elsif t == T_OBJECT
    zr_mark_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    zr_mark_ary(v)
  elsif t == T_HASH
    zr_mark_hash(v)
  elsif t == T_CREF
    zr_mark(RCref.klass(v))
    zr_mark(RCref.next(v))
  elsif t == T_ENV
    zr_mark_env(v)
  elsif t == T_PROC
    zr_mark_proc(v)
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
    zr_release_ivtab(ClassExt.iv(ext))
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
    zr_release_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    free(RArray.ptr(v))
  elsif t == T_HASH
    if RHash.entries(v) != 0
      free(RHash.entries(v))
    end
  elsif t == T_ENV
    free(REnv.slots(v))
  end
end
