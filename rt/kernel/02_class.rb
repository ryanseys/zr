# Classes: a name, a superclass, and a method table of (id, code, arity)
# rows searched in order. Method code takes `(recv, argc, argv)` and
# answers a Value.
Machine.struct :RClass, basic: RBasic, name: Word, superclass: Value, mtab: Ptr, mlen: Word, mcap: Word
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word
Machine.sig :method, [Value, Word, Ptr] => Value

sig [Word, Value] => Value
machine def zr_class_new(name, sup)
  c = zr_alloc(T_CLASS, zr_global(G_CLASS))
  RClass.set_name(c, name)
  RClass.set_superclass(c, sup)
  c
end

sig [Value, Word, Ptr, Word] => Void
machine def zr_define_method(klass, mid, fn, arity)
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
  end
end
