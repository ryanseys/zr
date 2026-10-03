module Zr::Kern
  # The constructors of `Data`. Each class that `Data.define` makes gets
  # `new` and `[]` as singleton builtins of its own. Thus a backtrace shows
  # `Point.new`, as in CRuby. Positional values become keywords in member
  # order, and then `initialize` receives the keywords.
  #
  # While the class's `initialize` is the core's (zr_data_initialize), the
  # keywords are not made: the values come directly from the arguments,
  # which is what `initialize` would do with them.
  #: (value, word, ptr, value, value) -> value
  def zr_data_new(recv, argc, argv, cref, blk)
    kwargs = Machine.value(QNIL)
    if zr_kw_take() != 0
      kwargs = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
      argc -= 1
    end
    members = zr_struct_members(recv)
    if members == QNIL
      members = zr_send(recv, Machine.id(:members), 0, 0)
      return members if members == QUNDEF
    end
    if argc > 0
      if kwargs != QNIL
        return zr_wrong_arity(argc + 1, 0)
      end
      if argc > RArray.len(members)
        return zr_wrong_arity_range(argc, 0, RArray.len(members))
      end
    end
    core = zr_data_core_init_p(recv)
    # A Data with no members still checks the keywords it is given.
    if core && argc == RArray.len(members) && kwargs == QNIL
      return zr_data_made(recv, zr_struct_values_of(argc, argc, argv))
    end
    if core && argc == 0 && kwargs != QNIL
      values = zr_data_values_from(members, kwargs)
      return values if values == QUNDEF
      if values != QNIL
        return zr_data_made(recv, values)
      end
    end
    if argc > 0
      kwargs = zr_hash_new()
      i = 0
      while i < argc
        zr_hash_store(kwargs, zr_ary_at(members, i), Machine.value(Machine.load64(argv + (i * 8), 0)))
        i += 1
      end
    end
    if kwargs == QNIL
      kwargs = zr_hash_new()
    end
    o = zr_class_allocate(recv)
    return o if o == QUNDEF
    # Each member is nil until `initialize` sets it. This is what a read
    # returns when a subclass's initialize does not call super.
    zr_ivar_set(o, Machine.id(:__values__), zr_struct_values_of(RArray.len(members), 0, Machine.ptr(0)))
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(kwargs))
    Task.set_kw(zr_task(), 1)
    r = zr_send_blk(o, Machine.id(:initialize), 1, slot, blk)
    return r if r == QUNDEF
    o
  end

  # Whether the instances of `klass` run the core's `Data#initialize`, so
  # that `new` can make their values itself.
  #: (value) -> bool
  def zr_data_core_init_p(klass)
    e = zr_find_method(klass, Machine.id(:initialize))
    e != 0 && MEntry.kind(e) == KIND_BUILTIN && MEntry.fn(e) == Machine.addr(:zr_data_initialize)
  end

  # A new instance of `klass` with `values`, frozen, as `Data#initialize`
  # leaves it.
  #: (value, value) -> value
  def zr_data_made(klass, values)
    o = zr_class_allocate(klass)
    return o if o == QUNDEF
    zr_data_fill(o, values)
    o
  end

  # Sets the values of `o` and freezes both, as rb_data_initialize_m does.
  #: (value, value) -> value
  def zr_data_fill(o, values)
    zr_obj_freeze(values, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
    r = zr_ivar_set(o, Machine.id(:__values__), values)
    return r if r == QUNDEF
    zr_obj_freeze(o, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  # The values that the keywords Hash `h` gives, in the order of
  # `members`, when it names each member once and nothing else. Returns nil
  # when it does not (`Data#initialize` then raises), and undef when a key's
  # own `eql?` raised.
  #: (value, value) -> value
  def zr_data_values_from(members, h)
    n = RArray.len(members)
    if RHash.live(h) != n
      return Machine.value(QNIL)
    end
    values = zr_ary_new(n)
    i = 0
    while i < n
      e = zr_hash_entry(h, zr_ary_at(members, i))
      if e == HASH_RAISED
        return Machine.value(QUNDEF)
      end
      if e == 0
        return Machine.value(QNIL)
      end
      Machine.store64(RArray.ptr(values) + (i * 8), 0, Machine.word(HEntry.value(e)))
      i += 1
    end
    RArray.set_len(values, n)
    values
  end

  # `Data#initialize`, as rb_data_initialize_m: the keywords name each
  # member once. That call fills the values here. All others (a missing or
  # an unknown keyword, a value by position) go to the core's
  # `initialize_members` (lib/zr/runtime/core/data.rb), which raises.
  #: (value, word, ptr, value, value) -> value
  def zr_data_initialize(recv, argc, argv, cref, blk)
    kw = zr_kw_take()
    members = zr_struct_members(zr_real_class(recv))
    if members != QNIL && argc == kw && (argc == 1 || RArray.len(members) == 0)
      values = argc == 0 ? zr_ary_new(0) : zr_data_values_from(members, Machine.value(Machine.load64(argv, 0)))
      return values if values == QUNDEF
      if values != QNIL
        r = zr_data_fill(recv, values)
        return r == QUNDEF ? r : Machine.value(QNIL)
      end
    end
    Task.set_kw(zr_task(), kw)
    zr_send(recv, Machine.id(:initialize_members), argc, argv)
  end

  # Defines the two constructors on the singleton class of `klass`.
  #: (value) -> value
  def zr_data_constructors(klass)
    zr_builtin(zr_singleton_class(klass), Machine.id(:new), Machine.addr(:zr_data_new), 0 - 1)
    zr_builtin(zr_singleton_class(klass), Machine.id(:[]), Machine.addr(:zr_data_new), 0 - 1)
    klass
  end

  # Defines `Data#initialize` on `klass`, which is Data.
  #: (value) -> value
  def zr_data_builtins(klass)
    zr_builtin(klass, Machine.id(:initialize), Machine.addr(:zr_data_initialize), 0 - 1)
    klass
  end
end
