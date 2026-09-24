# The constructors of `Data`. Each class that `Data.define` makes gets
# `new` and `[]` as singleton builtins of its own. Thus a backtrace shows
# `Point.new`, as in CRuby. Positional values become keywords in member
# order, and then `initialize` receives the keywords.
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
  # Each member is nil until `initialize` sets it. This is what a read
  # returns when a subclass's initialize does not call super.
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

# Defines the two constructors on the singleton class of `klass`.
sig [Value] => Value
machine def zr_data_constructors(klass)
  zr_builtin(zr_singleton_class(klass), Machine.id(:new), Machine.addr(:zr_data_new), 0 - 1)
  zr_builtin(zr_singleton_class(klass), Machine.id(:[]), Machine.addr(:zr_data_new), 0 - 1)
  klass
end
