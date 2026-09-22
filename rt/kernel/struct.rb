# Struct accessors (rt/core/struct.rb, and Data's readers): a member's
# reader and writer are entries of their own, as an attr_accessor's
# are, with the member's index in `fn` and the row guess for the
# values Array in `ivar`. The values are the hidden instance variable
# `__values__`, an Array the constructor makes; a struct `allocate`
# made has none until a write, and reads nil. An accessor has no frame,
# so its arity error is the caller's, and a trace sees a C call.
KIND_STRUCT_AREF = 10
KIND_STRUCT_ASET = 11

# A public reader per member of `members` on `klass`, with no source
# location, as ruby's answer.
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

# A public writer `member=` per member of `members` on `klass`.
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

# A hit on a reader entry at a compiled site. The road most reads take
# is written out here, with no call on it: a plain object outside a
# ractor, whose row the entry's cell guesses holds its values, an Array
# the member's index is within. Anything else -- a ractor, a struct
# with no values yet, a stale guess -- is `zr_struct_get`'s. A struct
# member went through five defs a read (the entry, `zr_struct_get`,
# `zr_ivar_get_cached`, `zr_ivar_row_guessed`, `zr_ary_at`), and
# `bm_structaref` was a third slower than ruby for it.
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

# A hit on a writer entry at a compiled site: the same road, with the
# frozen test and the barrier a store owes. A member past the values'
# length (a struct made by `allocate`, `Struct#values_store` not yet
# run) is `zr_struct_set`'s.
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

# The values Array of a struct on the guessed road, or QUNDEF where the
# road does not hold: `recv` is a plain object outside a ractor, the
# row the entry's cell guesses is `__values__`, and it holds an Array
# (nil until `Struct#values_store` runs). The row guess is
# `zr_ivar_guess_row`'s, written out so the entry stays a leaf.
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

# The member the entry `e` reads: nil while the struct has no values.
sig [Value, Ptr] => Value
machine def zr_struct_get(recv, e)
  values = zr_ivar_get_cached(recv, Machine.id(:__values__), MEntry.ivar(e))
  if values == QUNDEF || values == QNIL
    return values
  end
  zr_ary_at(values, Machine.word(MEntry.fn(e)))
end

# `v` into the member the entry `e` writes, making the values first
# when the struct has none.
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

# The values of a struct that has none yet: one nil per member of its
# class (the nearest class holding `__members__`), kept in `__values__`
# as `Struct#values_store` keeps them.
sig [Value] => Value
machine def zr_struct_values_new(recv)
  k = zr_real_class(recv)
  members = zr_ivar_get(k, Machine.id(:__members__))
  while members == QNIL
    k = RClass.superclass(k)
    members = zr_ivar_get(k, Machine.id(:__members__))
  end
  n = RArray.len(members)
  values = zr_ary_new(n)
  i = 0
  while i < n
    zr_ary_push(values, Machine.value(QNIL))
    i += 1
  end
  r = zr_ivar_set(recv, Machine.id(:__values__), values)
  r == QUNDEF ? r : values
end

# Whether entries of `kind` keep a word of their own in `fn` (an
# accessor's ivar id, a struct member's index) rather than a function.
sig [Word] => Bool
machine def zr_word_entry_p(kind)
  kind == KIND_ATTR_READER || kind == KIND_ATTR_WRITER || kind == KIND_STRUCT_AREF || kind == KIND_STRUCT_ASET
end
