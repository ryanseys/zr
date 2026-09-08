# Classes: a name, a superclass, and a method table of (id, code, arity)
# rows searched in order. Method code takes `(recv, argc, argv)` and
# answers a Value.
Machine.struct :RClass, basic: RBasic, name: Word, superclass: Value, mtab: Ptr, mlen: Word, mcap: Word
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr
Machine.sig :method, [Value, Word, Ptr] => Value

sig [Word, Value] => Value
machine def zr_class_new(name, sup)
  c = zr_alloc(T_CLASS, zr_global(G_CLASS))
  RClass.set_name(c, name)
  RClass.set_superclass(c, sup)
  c
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
  elsif mid == Machine.id(:!)
    GATE_NOT
  else
    0
  end
end

# A definition; the first one of each builtin operator is the runtime's
# own and leaves the gate clear, a later one sets it. `meta` is the
# compiled def's own FrameMeta, or 0 for a builtin, which gets one here.
sig [Value, Word, Ptr, Word, Word, Ptr] => Void
machine def zr_define_method(klass, mid, fn, arity, kind, meta)
  if meta == 0
    meta = malloc(FrameMeta.size)
    FrameMeta.set_file(meta, 0)
    FrameMeta.set_file_len(meta, 0)
    FrameMeta.set_kind(meta, kind)
    FrameMeta.set_line(meta, 0)
  end
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  if zr_find_method(klass, mid) != 0
    g = zr_gates()
    Machine.store64(g, 0, Machine.load64(g, 0) | zr_gate_bit(klass, mid))
  end
  n = RClass.mlen(klass)
  if n == RClass.mcap(klass)
    cap = n * 2
    if cap < 8
      cap = 8
    end
    tab = malloc(cap * MEntry.size)
    old = RClass.mtab(klass)
    if old != 0
      zr_memcpy(tab, old, n * MEntry.size)
      free(old)
    end
    RClass.set_mtab(klass, tab)
    RClass.set_mcap(klass, cap)
  end
  e = RClass.mtab(klass) + (n * MEntry.size)
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  RClass.set_mlen(klass, n + 1)
end

# The entry for `mid` on `klass` or an ancestor, or 0.
sig [Value, Word] => Ptr
machine def zr_find_method(klass, mid)
  while klass != QNIL
    n = RClass.mlen(klass)
    tab = RClass.mtab(klass)
    i = 0
    while i < n
      e = tab + (i * MEntry.size)
      if MEntry.mid(e) == mid
        return e
      end
      i += 1
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

# What a cell holds besides its class: marked by type.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_CLASS || t == T_MODULE
    zr_mark(RClass.superclass(v))
  elsif t == T_EXCEPTION
    zr_mark(RException.message(v))
  end
end

# What a cell owns outside the arena: freed with it.
sig [Value] => Void
machine def zr_release(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_CLASS || t == T_MODULE
    if RClass.mtab(v) != 0
      free(RClass.mtab(v))
    end
  elsif t == T_STRING
    if RString.ptr(v) != 0
      free(RString.ptr(v))
    end
  elsif t == T_EXCEPTION
    if RException.rows(v) != 0
      free(RException.rows(v))
    end
  end
end
