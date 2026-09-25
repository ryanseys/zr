# Struct accessors (runtime/core/struct.rb, and Data's readers). Each
# member reader and writer is a method entry of its own, as for
# attr_accessor. `fn` contains the member's index, and `ivar` contains the
# inline cache hint for the values Array. The values are in the hidden
# instance variable `__values__`, an Array that the constructor makes. A
# struct from `allocate` has no values until a write, and its reads
# return nil. An accessor has no frame, so its arity error comes from the
# caller, and a trace sees a C call.
KIND_STRUCT_AREF = 10
KIND_STRUCT_ASET = 11

# Defines a public reader on `klass` for each member of `members`, with
# no source location, as ruby does.
sig [Value, Value] => Value
machine def zr_struct_readers(klass, members)
  i = 0
  while i < RArray.len(members)
    r = zr_define_method_as(klass, zr_sym2id(zr_ary_at(members, i)), Machine.ptr(i), 0, KIND_STRUCT_AREF, 0, Machine.value(QNIL), VIS_PUBLIC)
    return r if r == QUNDEF
    i += 1
  end
  Machine.value(QNIL)
end

# Defines a public writer `member=` on `klass` for each member of `members`.
sig [Value, Value] => Value
machine def zr_struct_writers(klass, members)
  i = 0
  while i < RArray.len(members)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_sym(b, zr_sym2id(zr_ary_at(members, i)))
    zr_buf_byte(b, 61)
    setter = zr_intern(Buf.ptr(b), Buf.len(b))
    zr_buf_free(b)
    r = zr_define_method_as(klass, setter, Machine.ptr(i), 1, KIND_STRUCT_ASET, 0, Machine.value(QNIL), VIS_PUBLIC)
    return r if r == QUNDEF
    i += 1
  end
  Machine.value(QNIL)
end

# Runs a reader entry that a compiled site finds. The common case runs
# here with no call: a plain object outside a ractor, whose ivar entry at
# the cached index contains the values, an Array that contains the
# member's index. All other cases (a ractor, a struct with no values, a
# stale cached index) go to `zr_struct_get`. Through that path a member
# read takes five calls (the entry, `zr_struct_get`, `zr_ivar_get_cached`,
# `zr_ivar_row_guessed`, `zr_ary_at`), which made `bm_structaref` a third
# slower than ruby.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_struct_aref_fn(recv, argc, argv, e, blk, found)
  if argc != 0
    return zr_wrong_arity(argc, 0)
  end
  t = zr_task()
  Task.set_kw(t, 0)
  values = zr_struct_values_guessed(recv, e, t)
  if values != QUNDEF
    i = Machine.word(MEntry.fn(e))
    if i < RArray.len(values)
      return Machine.value(Machine.load64(RArray.ptr(values) + (i * 8), 0))
    end
  end
  zr_struct_get(recv, e)
end

# Runs a writer entry that a compiled site finds. It uses the same fast
# path, plus the frozen check and the write barrier that a store needs.
# A member past the end of the values (a struct from `allocate`, before
# `zr_struct_values` runs) goes to `zr_struct_set`.
sig [Value, Word, Ptr, Ptr, Value, Value] => Value
machine def zr_struct_aset_fn(recv, argc, argv, e, blk, found)
  if argc != 1
    return zr_wrong_arity(argc, 1)
  end
  t = zr_task()
  Task.set_kw(t, 0)
  v = Machine.value(Machine.load64(argv, 0))
  values = zr_struct_values_guessed(recv, e, t)
  if values != QUNDEF && (RBasic.flags(recv) & FL_FREEZE) == 0
    i = Machine.word(MEntry.fn(e))
    if i < RArray.len(values)
      Machine.store64(RArray.ptr(values) + (i * 8), 0, Machine.word(v))
      zr_write_barrier(values, v)
      return v
    end
  end
  zr_struct_set(recv, e, v)
end

# Returns the values Array of a struct through the cached index, or
# QUNDEF when the fast path does not apply. The fast path needs three
# things: `recv` is a plain object outside a ractor, the ivar entry at
# the cached index is `__values__`, and it contains an Array (it is nil
# until `zr_struct_values` runs). The lookup is a copy of
# `zr_ivar_guess_row`, inline so that the entry makes no calls.
sig [Value, Ptr, Ptr] => Value
machine def zr_struct_values_guessed(recv, e, t)
  if zr_special_p(recv) || (RBasic.flags(recv) & T_MASK) != T_OBJECT || Task.ractor(t) != 0
    return Machine.value(QUNDEF)
  end
  tab = RObject.iv(recv)
  ic = MEntry.ivar(e)
  i = IvarCache.index(ic)
  if i >= IvTab.len(tab)
    return Machine.value(QUNDEF)
  end
  row = IvTab.rows(tab) + (i * IvEntry.size)
  if IvEntry.id(row) != Machine.id(:__values__)
    return Machine.value(QUNDEF)
  end
  values = IvEntry.value(row)
  if zr_special_p(values) || (RBasic.flags(values) & T_MASK) != T_ARRAY
    return Machine.value(QUNDEF)
  end
  values
end
Machine.inline :zr_struct_values_guessed

# Returns the member that the entry `e` reads, or nil while the struct
# has no values.
sig [Value, Ptr] => Value
machine def zr_struct_get(recv, e)
  values = zr_ivar_get_cached(recv, Machine.id(:__values__), MEntry.ivar(e))
  if values == QUNDEF || values == QNIL
    return values
  end
  zr_ary_at(values, Machine.word(MEntry.fn(e)))
end

# Writes `v` into the member that the entry `e` writes. If the struct
# has no values, it makes them first.
sig [Value, Ptr, Value] => Value
machine def zr_struct_set(recv, e, v)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  values = zr_ivar_get_cached(recv, Machine.id(:__values__), MEntry.ivar(e))
  return values if values == QUNDEF
  if values == QNIL
    values = zr_struct_values_new(recv)
    return values if values == QUNDEF
  end
  r = zr_ary_store(values, Machine.word(MEntry.fn(e)), v)
  r == QUNDEF ? r : v
end

# Makes the values of a struct that has none: one nil for each member of
# its class, in `__values__`.
sig [Value] => Value
machine def zr_struct_values_new(recv)
  values = zr_struct_values_of(RArray.len(zr_struct_members(zr_real_class(recv))), 0, Machine.ptr(0))
  r = zr_ivar_set(recv, Machine.id(:__values__), values)
  r == QUNDEF ? r : values
end

# Returns the values of a struct, and makes them first if it has none.
sig [Value] => Value
machine def zr_struct_values(recv)
  values = zr_ivar_get(recv, Machine.id(:__values__))
  values == QNIL ? zr_struct_values_new(recv) : values
end

# Returns the members of a struct or Data class: the `__members__` of the
# nearest class that has them, as rb_struct_members reads them. Returns
# nil for a class with none (Struct and Data themselves).
sig [Value] => Value
machine def zr_struct_members(klass)
  e = zr_struct_row(klass)
  e == 0 ? Machine.value(QNIL) : IvEntry.value(e)
end

# Returns the ivar entry of `__members__` in the nearest class that has
# one, or 0. `Struct.new` and `Data.define` set it first, so the first
# entry is the guess, and a scan finds it in all other cases. A `new`
# reads the members, and a hash lookup for each class on the way cost a
# quarter of the time of `Struct.new(...).new(...)`.
sig [Value] => Ptr
machine def zr_struct_row(klass)
  while klass != QNIL
    t = ClassExt.iv(RClass.ext(klass))
    if IvTab.len(t) > 0
      if IvEntry.id(IvTab.rows(t)) == Machine.id(:__members__)
        return IvTab.rows(t)
      end
      e = zr_ivtab_row(t, Machine.id(:__members__))
      return e if e != 0
    end
    klass = RClass.superclass(klass)
  end
  Machine.ptr(0)
end

# Returns a new values Array of `n` values: the `argc` Values at `argv`,
# then nil for each other member. The Array is new, so no store needs a
# write barrier.
sig [Word, Word, Ptr] => Value
machine def zr_struct_values_of(n, argc, argv)
  values = zr_ary_new(n)
  zr_memcpy(RArray.ptr(values), argv, argc * 8)
  i = argc
  while i < n
    Machine.store64(RArray.ptr(values) + (i * 8), 0, Machine.word(QNIL))
    i += 1
  end
  RArray.set_len(values, n)
  values
end

# The values that the keywords Hash `h` names, in the order of
# `members`, nil for each member it does not name. Returns nil when it
# names something else (`initialize_members` then raises), and undef when
# a key's own `eql?` raised.
sig [Value, Value] => Value
machine def zr_struct_values_named(members, h)
  n = RArray.len(members)
  values = zr_struct_values_of(n, 0, Machine.ptr(0))
  found = 0
  i = 0
  while i < n
    e = zr_hash_entry(h, zr_ary_at(members, i))
    if e == HASH_RAISED
      return Machine.value(QUNDEF)
    end
    if e != 0
      Machine.store64(RArray.ptr(values) + (i * 8), 0, Machine.word(HEntry.value(e)))
      found += 1
    end
    i += 1
  end
  found == RHash.live(h) ? values : Machine.value(QNIL)
end

# `Struct#initialize`, as rb_struct_initialize_m. The two usual calls
# make the values here: values by position, with no Array for the
# arguments, and only keywords that name members, where the class takes
# them. All other calls (a keyword that is not a member, values by
# position to a class made with `keyword_init: true`, too many values)
# go to the core's `initialize_members` (runtime/core/struct.rb), which
# binds them or raises.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_struct_initialize(recv, argc, argv, cref, blk)
  kw = zr_kw_take()
  k = zr_real_class(recv)
  e = zr_struct_row(k)
  if kw == 0 && e != 0
    n = RArray.len(IvEntry.value(e))
    if argc <= n && (argc == 0 || zr_struct_keyword_init(k) != QTRUE)
      r = zr_ivar_set(recv, Machine.id(:__values__), zr_struct_values_of(n, argc, argv))
      return r == QUNDEF ? r : Machine.value(QNIL)
    end
  end
  if kw != 0 && argc == 1 && e != 0 && zr_struct_keyword_init(k) != QFALSE
    values = zr_struct_values_named(IvEntry.value(e), Machine.value(Machine.load64(argv, 0)))
    return values if values == QUNDEF
    if values != QNIL
      r = zr_ivar_set(recv, Machine.id(:__values__), values)
      return r == QUNDEF ? r : Machine.value(QNIL)
    end
  end
  Task.set_kw(zr_task(), kw)
  zr_send(recv, Machine.id(:initialize_members), argc, argv)
end

# The `keyword_init:` of a struct class: the `__keyword_init__` of the
# class that has the members, as rb_struct_s_keyword_init reads it.
# `Struct.new` sets it second, so the second entry is the guess.
sig [Value] => Value
machine def zr_struct_keyword_init(klass)
  while klass != QNIL
    t = ClassExt.iv(RClass.ext(klass))
    rows = IvTab.rows(t)
    if IvTab.len(t) > 1 && IvEntry.id(rows) == Machine.id(:__members__) && IvEntry.id(rows + IvEntry.size) == Machine.id(:__keyword_init__)
      return IvEntry.value(rows + IvEntry.size)
    end
    if IvTab.len(t) > 0 && zr_ivtab_row(t, Machine.id(:__members__)) != 0
      v = zr_ivtab_get(t, Machine.id(:__keyword_init__))
      return v == QUNDEF ? Machine.value(QNIL) : v
    end
    klass = RClass.superclass(klass)
  end
  Machine.value(QNIL)
end

# Defines `Struct#initialize` on `klass`, which is Struct.
sig [Value] => Value
machine def zr_struct_builtins(klass)
  zr_builtin(klass, Machine.id(:initialize), Machine.addr(:zr_struct_initialize), 0 - 1)
  klass
end

# Whether method entries of `kind` keep a data word in `fn` (an
# accessor's ivar id, a struct member's index) in place of a function.
sig [Word] => Bool
machine def zr_word_entry_p(kind)
  kind == KIND_ATTR_READER || kind == KIND_ATTR_WRITER || kind == KIND_STRUCT_AREF || kind == KIND_STRUCT_ASET
end
