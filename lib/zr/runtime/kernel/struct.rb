module Zr::Kern
  # Struct accessors (lib/zr/runtime/core/struct.rb, and Data's readers). Each
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
  #: (value, value) -> value
  def zr_struct_readers(klass, members)
    i = 0
    while i < RArray[members].len
      # A member named object_id warns as any new method over it does.
      if zr_program_started_p()
        zr_warn_dangerous(klass, zr_sym2id(zr_ary_at(members, i)), KIND_STRUCT_AREF)
      end
      r = zr_define_method_as(klass, zr_sym2id(zr_ary_at(members, i)), Machine.ptr(i), 0, KIND_STRUCT_AREF, 0, Machine.value(QNIL), VIS_PUBLIC)
      return r if r == QUNDEF
      i += 1
    end
    Machine.value(QNIL)
  end

  # Defines a public writer `member=` on `klass` for each member of `members`.
  #: (value, value) -> value
  def zr_struct_writers(klass, members)
    i = 0
    while i < RArray[members].len
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_sym(b, zr_sym2id(zr_ary_at(members, i)))
      zr_buf_byte(b, 61)
      setter = zr_intern(Buf[b].ptr, Buf[b].len)
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
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_struct_aref_fn(recv, argc, argv, e, blk, found)
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    t = zr_task()
    Task[t].kw = 0
    values = zr_struct_values_guessed(recv, e, t)
    if values != QUNDEF
      i = Machine.word(MEntry[e].fn)
      if i < RArray[values].len
        return Machine.value(Machine.load64(RArray[values].ptr + (i * 8), 0))
      end
    end
    zr_struct_get(recv, e)
  end

  # Runs a writer entry that a compiled site finds. It uses the same fast
  # path, plus the frozen check and the write barrier that a store needs.
  # A member past the end of the values (a struct from `allocate`, before
  # `zr_struct_values` runs) goes to `zr_struct_set`.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_struct_aset_fn(recv, argc, argv, e, blk, found)
    if argc != 1
      return zr_wrong_arity(argc, 1)
    end
    t = zr_task()
    Task[t].kw = 0
    v = Machine.value(Machine.load64(argv, 0))
    values = zr_struct_values_guessed(recv, e, t)
    if values != QUNDEF && (RBasic[recv].flags & FL_FREEZE) == 0
      i = Machine.word(MEntry[e].fn)
      if i < RArray[values].len
        Machine.store64(RArray[values].ptr + (i * 8), 0, Machine.word(v))
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
  #: (value, ptr, ptr) -> value
  def zr_struct_values_guessed(recv, e, t)
    if zr_special_p(recv) || (RBasic[recv].flags & T_MASK) != T_OBJECT || Task[t].ractor != 0
      return Machine.value(QUNDEF)
    end
    tab = Machine.ptr(RObject[recv].iv)
    ic = Machine.ptr(MEntry[e].ivar)
    i = IvarCache[ic].index
    if i >= IvTab[tab].len
      return Machine.value(QUNDEF)
    end
    row = IvTab[tab].rows + (i * IvEntry.size)
    if IvEntry[row].id != Machine.id(:__values__)
      return Machine.value(QUNDEF)
    end
    values = IvEntry[row].value
    if zr_special_p(values) || (RBasic[values].flags & T_MASK) != T_ARRAY
      return Machine.value(QUNDEF)
    end
    values
  end
  inline :zr_struct_values_guessed

  # Returns the member that the entry `e` reads, or nil while the struct
  # has no values.
  #: (value, ptr) -> value
  def zr_struct_get(recv, e)
    values = zr_ivar_get_cached(recv, Machine.id(:__values__), Machine.ptr(MEntry[e].ivar))
    if values == QUNDEF || values == QNIL
      return values
    end
    zr_ary_at(values, Machine.word(MEntry[e].fn))
  end

  # Writes `v` into the member that the entry `e` writes. If the struct
  # has no values, it makes them first.
  #: (value, ptr, value) -> value
  def zr_struct_set(recv, e, v)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    values = zr_ivar_get_cached(recv, Machine.id(:__values__), Machine.ptr(MEntry[e].ivar))
    return values if values == QUNDEF
    if values == QNIL
      values = zr_struct_values_new(recv)
      return values if values == QUNDEF
    end
    r = zr_ary_store(values, Machine.word(MEntry[e].fn), v)
    r == QUNDEF ? r : v
  end

  # Makes the values of a struct that has none: one nil for each member of
  # its class, in `__values__`.
  #: (value) -> value
  def zr_struct_values_new(recv)
    values = zr_struct_values_of(RArray[zr_struct_members(zr_real_class(recv))].len, 0, Machine.ptr(0))
    r = zr_ivar_set(recv, Machine.id(:__values__), values)
    r == QUNDEF ? r : values
  end

  # Returns the values of a struct, and makes them first if it has none.
  #: (value) -> value
  def zr_struct_values(recv)
    values = zr_ivar_get(recv, Machine.id(:__values__))
    values == QNIL ? zr_struct_values_new(recv) : values
  end

  # Returns the members of a struct or Data class: the `__members__` of the
  # nearest class that has them, as rb_struct_members reads them. Returns
  # nil for a class with none (Struct and Data themselves).
  #: (value) -> value
  def zr_struct_members(klass)
    e = zr_struct_row(klass)
    e == 0 ? Machine.value(QNIL) : IvEntry[e].value
  end

  # Returns the ivar entry of `__members__` in the nearest class that has
  # one, or 0. `Struct.new` and `Data.define` set it first, so the first
  # entry is the guess, and a scan finds it in all other cases. A `new`
  # reads the members, and a hash lookup for each class on the way cost a
  # quarter of the time of `Struct.new(...).new(...)`.
  #: (value) -> ptr
  def zr_struct_row(klass)
    while klass != QNIL
      t = Machine.ptr(ClassExt[RClass[klass].ext].iv)
      if IvTab[t].len > 0
        if IvEntry[IvTab[t].rows].id == Machine.id(:__members__)
          return IvTab[t].rows
        end
        e = zr_ivtab_row(t, Machine.id(:__members__))
        return e if e != 0
      end
      klass = RClass[klass].superclass
    end
    Machine.ptr(0)
  end

  # Returns a new values Array of `n` values: the `argc` Values at `argv`,
  # then nil for each other member. The Array is new, so no store needs a
  # write barrier.
  #: (word, word, ptr) -> value
  def zr_struct_values_of(n, argc, argv)
    values = zr_ary_new(n)
    zr_memcpy(RArray[values].ptr, argv, argc * 8)
    i = argc
    while i < n
      Machine.store64(RArray[values].ptr + (i * 8), 0, Machine.word(QNIL))
      i += 1
    end
    RArray[values].len = n
    values
  end

  # The values that the keywords Hash `h` names, in the order of
  # `members`, nil for each member it does not name. Returns nil when it
  # names something else (`initialize_members` then raises), and undef when
  # a key's own `eql?` raised.
  #: (value, value) -> value
  def zr_struct_values_named(members, h)
    n = RArray[members].len
    values = zr_struct_values_of(n, 0, Machine.ptr(0))
    found = 0
    i = 0
    while i < n
      e = zr_hash_entry(h, zr_ary_at(members, i))
      if e == HASH_RAISED
        return Machine.value(QUNDEF)
      end
      if e != 0
        Machine.store64(RArray[values].ptr + (i * 8), 0, Machine.word(HEntry[e].value))
        found += 1
      end
      i += 1
    end
    found == RHash[h].live ? values : Machine.value(QNIL)
  end

  # `Struct#initialize`, as rb_struct_initialize_m. The two usual calls
  # make the values here: values by position, with no Array for the
  # arguments, and only keywords that name members, where the class takes
  # them. All other calls (a keyword that is not a member, values by
  # position to a class made with `keyword_init: true`, too many values)
  # go to the core's `initialize_members` (lib/zr/runtime/core/struct.rb), which
  # binds them or raises.
  #: (value, word, ptr, value, value) -> value
  def zr_struct_initialize(recv, argc, argv, cref, blk)
    kw = zr_kw_take()
    k = zr_real_class(recv)
    e = zr_struct_row(k)
    if kw == 0 && e != 0
      n = RArray[IvEntry[e].value].len
      if argc <= n && (argc == 0 || zr_struct_keyword_init(k) != QTRUE)
        r = zr_ivar_set(recv, Machine.id(:__values__), zr_struct_values_of(n, argc, argv))
        return r == QUNDEF ? r : Machine.value(QNIL)
      end
    end
    if kw != 0 && argc == 1 && e != 0 && zr_struct_keyword_init(k) != QFALSE
      values = zr_struct_values_named(IvEntry[e].value, Machine.value(Machine.load64(argv, 0)))
      return values if values == QUNDEF
      if values != QNIL
        r = zr_ivar_set(recv, Machine.id(:__values__), values)
        return r == QUNDEF ? r : Machine.value(QNIL)
      end
    end
    Task[zr_task()].kw = kw
    zr_send(recv, Machine.id(:initialize_members), argc, argv)
  end

  # The `keyword_init:` of a struct class: the `__keyword_init__` of the
  # class that has the members, as rb_struct_s_keyword_init reads it.
  # `Struct.new` sets it second, so the second entry is the guess.
  #: (value) -> value
  def zr_struct_keyword_init(klass)
    while klass != QNIL
      t = Machine.ptr(ClassExt[RClass[klass].ext].iv)
      rows = IvTab[t].rows
      if IvTab[t].len > 1 && IvEntry[rows].id == Machine.id(:__members__) && IvEntry[rows + IvEntry.size].id == Machine.id(:__keyword_init__)
        return IvEntry[rows + IvEntry.size].value
      end
      if IvTab[t].len > 0 && zr_ivtab_row(t, Machine.id(:__members__)) != 0
        v = zr_ivtab_get(t, Machine.id(:__keyword_init__))
        return v == QUNDEF ? Machine.value(QNIL) : v
      end
      klass = RClass[klass].superclass
    end
    Machine.value(QNIL)
  end

  # `Struct#to_a`, `deconstruct` and `values`: a copy of the values.
  #: (value, word, ptr, value, value) -> value
  def zr_struct_to_a(recv, argc, argv, cref, blk)
    values = zr_struct_values(recv)
    return values if values == QUNDEF
    zr_ary_of(RArray[values].len, RArray[values].ptr)
  end

  # `Struct#initialize_copy`, which fills a `dup` or a `clone`. The copy
  # already has the other struct's entries, so it only needs values of its
  # own. A copy from anything but an unfrozen struct of the same class goes
  # to the core's `initialize_copy_members`, which checks it as
  # Kernel#initialize_copy does.
  #: (value, word, ptr, value, value) -> value
  def zr_struct_initialize_copy(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if other != recv && !zr_special_p(other) && zr_real_class(other) == zr_real_class(recv) && !zr_frozen_p(recv)
      values = zr_ivar_get(other, Machine.id(:__values__))
      if values != QNIL
        r = zr_ivar_set(recv, Machine.id(:__values__), zr_ary_of(RArray[values].len, RArray[values].ptr))
        return r == QUNDEF ? r : recv
      end
    end
    zr_send(recv, Machine.id(:initialize_copy_members), 1, argv)
  end

  # Defines the kernel's entries of Struct on `klass`, which is Struct.
  #: (value) -> value
  def zr_struct_builtins(klass)
    zr_builtin(klass, Machine.id(:initialize), Machine.addr(:zr_struct_initialize), 0 - 1)
    zr_builtin_private(klass, Machine.id(:initialize_copy), Machine.addr(:zr_struct_initialize_copy), 1)
    zr_builtin(klass, Machine.id(:to_a), Machine.addr(:zr_struct_to_a), 0)
    zr_builtin(klass, Machine.id(:deconstruct), Machine.addr(:zr_struct_to_a), 0)
    zr_builtin(klass, Machine.id(:values), Machine.addr(:zr_struct_to_a), 0)
    klass
  end

  # Whether method entries of `kind` keep a data word in `fn` (an
  # accessor's ivar id, a struct member's index) in place of a function.
  #: (word) -> bool
  def zr_word_entry_p(kind)
    kind == KIND_ATTR_READER || kind == KIND_ATTR_WRITER || kind == KIND_STRUCT_AREF || kind == KIND_STRUCT_ASET
  end
end
