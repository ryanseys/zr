# `Data`'s constructors: every class `Data.define` makes gets `new`
# and `[]` as its own singleton builtins, so a backtrace names them
# `Point.new` as CRuby's does. Positional values become keywords by
# member order, then `initialize` takes the keywords.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_data_new(recv, argc, argv, cref, blk)
  kwargs = Machine.value(QNIL)
  if zr_kw_take() != 0
    kwargs = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    argc -= 1
  end
  members = zr_send(recv, Machine.id(:members), 0, 0)
  return members if members == QUNDEF
  if argc > 0
    if kwargs != QNIL
      return zr_wrong_arity(argc + 1, 0)
    end
    if argc > RArray.len(members)
      return zr_wrong_arity_range(argc, 0, RArray.len(members))
    end
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
  # Every member reads nil until `initialize` sets it, as it does when a
  # subclass's initialize never calls super.
  values = zr_ary_new(RArray.len(members))
  i = 0
  while i < RArray.len(members)
    zr_ary_push(values, Machine.value(QNIL))
    i += 1
  end
  zr_ivar_set(o, Machine.id(:__values__), values)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(kwargs))
  Task.set_kw(zr_task(), 1)
  r = zr_send(o, Machine.id(:initialize), 1, slot)
  return r if r == QUNDEF
  o
end

# The two constructors onto the class's singleton.
sig [Value] => Value
machine def zr_data_constructors(klass)
  zr_builtin(zr_singleton_class(klass), Machine.id(:new), Machine.addr(:zr_data_new), 0 - 1)
  zr_builtin(zr_singleton_class(klass), Machine.id(:[]), Machine.addr(:zr_data_new), 0 - 1)
  klass
end
