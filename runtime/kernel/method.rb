# Method and UnboundMethod contain a copy of the method entry, the
# module where the lookup found it (`owner`), the class of the lookup
# (`klass`), and the receiver. An UnboundMethod has no receiver.
Machine.struct :RMethod, basic: RBasic, recv: Value, klass: Value, owner: Value, entry: MEntry
T_METHOD = 29
G_METHOD = 33
G_UNBOUND_METHOD = 34

PARAM_REQ = 0
PARAM_OPT = 1
PARAM_REST = 2
PARAM_KEYREQ = 3
PARAM_KEY = 4
PARAM_KEYREST = 5
PARAM_BLOCK = 6
PARAM_NOKEY = 7

sig [Value] => Void
machine def zr_mark_method(m)
  zr_mark(RMethod.recv(m))
  zr_mark(RMethod.klass(m))
  zr_mark(RMethod.owner(m))
  zr_mark_entry(RMethod.entry(m))
end

# Returns the module in `klass`'s ancestor list whose own method table
# has `mid`, or nil.
sig [Value, Word] => Value
machine def zr_method_owner(klass, mid)
  k = klass
  while k != QNIL
    e = zr_find_method_at(k, mid)
    if e != 0
      if MEntry.kind(e) == KIND_UNDEF
        return Machine.value(QNIL)
      end
      if zr_type(k) == T_ICLASS
        return RClass.attached(k)
      end
      return k
    end
    k = RClass.superclass(k)
  end
  Machine.value(QNIL)
end

# Raises the NameError for `mid` on `klass`. When `vis` is public (no
# such method), the message is `undefined method 'x' for class 'C'`. If
# not, it is `method 'x' for class 'C' is private` or protected.
sig [Value, Word, Word] => Value
machine def zr_undefined_method(klass, mid, vis)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if vis == VIS_PUBLIC
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
  else
    zr_buf_push(b, Machine.bytes("method '"), 8)
  end
  zr_buf_sym(b, mid)
  if zr_type(klass) == T_MODULE
    zr_buf_push(b, Machine.bytes("' for module '"), 14)
  else
    zr_buf_push(b, Machine.bytes("' for class '"), 13)
  end
  s = zr_inspect(klass)
  return s if s == QUNDEF
  zr_buf_str(b, s)
  zr_buf_byte(b, 39)
  if vis == VIS_PRIVATE
    zr_buf_push(b, Machine.bytes(" is private"), 11)
  elsif vis == VIS_PROTECTED
    zr_buf_push(b, Machine.bytes(" is protected"), 13)
  end
  e = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
  zr_exc_detail(e, Machine.id(:receiver), klass)
  zr_raise(e)
end

# Returns the Method (with a receiver) or the UnboundMethod (`recv` is
# undef) for `mid` on `klass`, or raises the NameError.
sig [Value, Value, Word] => Value
machine def zr_method_new(recv, klass, mid)
  e = zr_find_method(klass, mid)
  if e == 0
    if recv != QUNDEF && zr_respond_to_missing_p(recv, mid)
      return zr_method_missing_new(recv, klass, mid)
    end
    return zr_undefined_method(klass, mid, VIS_PUBLIC)
  end
  owner = zr_found_refinement()
  if owner == QNIL
    owner = zr_method_owner(klass, mid)
  end
  m = zr_alloc(T_METHOD, zr_global(recv == QUNDEF ? G_UNBOUND_METHOD : G_METHOD), RMethod.size)
  RMethod.set_recv(m, recv)
  RMethod.set_klass(m, klass)
  RMethod.set_owner(m, owner)
  zr_memcpy(RMethod.entry(m), e, MEntry.size)
  zr_write_barrier_all(m)
  m
end

# Makes a Method for a name that the receiver handles only through
# `method_missing`. Its owner is the class of the lookup (the singleton
# class if the receiver has one), and it takes any number of arguments.
sig [Value, Value, Word] => Value
machine def zr_method_missing_new(recv, klass, mid)
  m = zr_alloc(T_METHOD, zr_global(G_METHOD), RMethod.size)
  RMethod.set_recv(m, recv)
  RMethod.set_klass(m, klass)
  RMethod.set_owner(m, klass)
  e = RMethod.entry(m)
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, 0)
  MEntry.set_direct(e, 0)
  MEntry.set_arity(e, 0 - 1)
  MEntry.set_kind(e, KIND_MISSING)
  MEntry.set_meta(e, 0)
  MEntry.set_cref(e, Machine.value(QNIL))
  MEntry.set_vis(e, VIS_PUBLIC)
  MEntry.set_orig(e, mid)
  MEntry.set_from(e, Machine.value(QNIL))
  MEntry.set_core(e, 0)
  MEntry.set_concealed(e, 0)
  IvarCache.set_index(MEntry.ivar(e), 0)
  zr_methods_changed()
  m
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_method_new(recv, zr_box_view(zr_class_of(recv)), Machine.load64(slot, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_instance_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_method_new(Machine.value(QUNDEF), recv, Machine.load64(slot, 0))
end

# `public_method` and `public_instance_method`: the same as `method`
# and `instance_method`, but only when the method is public.
sig [Value, Value, Word] => Value
machine def zr_public_method_new(recv, klass, mid)
  m = zr_method_new(recv, klass, mid)
  return m if m == QUNDEF
  vis = MEntry.vis(RMethod.entry(m))
  return m if vis == VIS_PUBLIC
  zr_undefined_method(klass, mid, vis)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_public_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_public_method_new(recv, zr_box_view(zr_class_of(recv)), Machine.load64(slot, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_instance_method(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_public_method_new(Machine.value(QUNDEF), recv, Machine.load64(slot, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_call(recv, argc, argv, cref, blk)
  if blk != QNIL
    RProc.set_passed(blk, 1)
  end
  zr_method_invoke(recv, argc, argv, blk)
end

# The block function of `Method#to_proc`: the Proc's self is the Method.
sig [Value, Word, Ptr, Value] => Value
machine def zr_method_block(p, argc, argv, blk)
  zr_method_invoke(RProc.self(p), argc, argv, blk)
end

# Calls the Method's entry on its receiver. The lookup finds the
# ancestor that has the name, and `super` in the body continues from
# that ancestor.
sig [Value, Word, Ptr, Value] => Value
machine def zr_method_invoke(m, argc, argv, blk)
  zr_find_method(RMethod.klass(m), MEntry.mid(RMethod.entry(m)))
  zr_invoke(RMethod.entry(m), RMethod.recv(m), argc, argv, blk, zr_kw_take())
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_to_proc(recv, argc, argv, cref, blk)
  zr_native_proc(Machine.addr(:zr_method_block), recv)
end

# Returns the FrameMeta that gives the parameters, arity and location of
# a method entry: its own for a def, its block's for a `define_method`
# body, and 0 for a builtin.
sig [Ptr] => Ptr
machine def zr_method_meta(e)
  if MEntry.kind(e) == KIND_DEF
    return MEntry.meta(e)
  end
  if MEntry.kind(e) == KIND_BMETHOD
    return RProc.meta(MEntry.cref(e))
  end
  0
end

# A compiled def has the arity of its parameters. A builtin's arity is
# in its entry. A core def returns what C returns (-1 for any optional
# count), unless CRuby also writes that method in Ruby.
sig [Value] => Word
machine def zr_method_arity_of(m)
  e = RMethod.entry(m)
  meta = zr_method_meta(e)
  if meta != 0
    if FrameMeta.file_len(meta) == 0 && FrameMeta.ruby(meta) == 0 && FrameMeta.arity(meta) < 0
      return 0 - 1
    end
    return FrameMeta.arity(meta)
  end
  MEntry.fn(e) == Machine.addr(:zr_f_notimplement) ? 0 : MEntry.arity(e)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_arity(recv, argc, argv, cref, blk)
  zr_fix(zr_method_arity_of(recv))
end

# Returns the entries of a parameter table in the form that `parameters`
# returns. For a plain proc, required parameters are optional.
sig [Ptr, Bool] => Value
machine def zr_param_rows(table, lenient)
  out = zr_ary_new(4)
  n = Machine.load64(table, 0)
  i = 0
  while i < n
    row = zr_ary_new(2)
    kind = Machine.load64(table + 8 + (i * 16), 0)
    if lenient && kind == PARAM_REQ
      kind = PARAM_OPT
    end
    zr_ary_push(row, zr_sym(zr_param_kind_name(kind)))
    id = Machine.load64(table + 16 + (i * 16), 0)
    if id != 0
      zr_ary_push(row, zr_sym(id))
    end
    zr_ary_push(out, row)
    i += 1
  end
  out
end

# Returns the parameter entries for a C method: `[:rest]` for any
# count, or one `[:req]` for each argument.
sig [Word] => Value
machine def zr_arity_rows(arity)
  out = zr_ary_new(4)
  if arity < 0
    row = zr_ary_new(1)
    zr_ary_push(row, zr_sym(Machine.id(:rest)))
    zr_ary_push(out, row)
    return out
  end
  i = 0
  while i < arity
    row = zr_ary_new(1)
    zr_ary_push(row, zr_sym(Machine.id(:req)))
    zr_ary_push(out, row)
    i += 1
  end
  out
end

sig [Value] => Value
machine def zr_method_rows(m)
  e = RMethod.entry(m)
  meta = zr_method_meta(e)
  # A core def returns what C returns, unless CRuby also writes that
  # method in Ruby. A define_method body, also in the core, returns its
  # block's table.
  if meta != 0 && (FrameMeta.file_len(meta) > 0 || FrameMeta.ruby(meta) != 0 || MEntry.kind(e) == KIND_BMETHOD)
    return zr_param_rows(FrameMeta.params(meta), false)
  end
  # A struct writer calls its one parameter `_`, as ruby does.
  if MEntry.kind(e) == KIND_STRUCT_ASET
    row = zr_ary_new(2)
    zr_ary_push(row, zr_sym(Machine.id(:req)))
    zr_ary_push(row, zr_sym(Machine.id(:_)))
    out = zr_ary_new(1)
    zr_ary_push(out, row)
    return out
  end
  zr_arity_rows(zr_method_arity_of(m))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_parameters(recv, argc, argv, cref, blk)
  zr_method_rows(recv)
end

# The required count of a parameter table (all required keywords count
# as one), and whether the table takes any number of arguments.
sig [Ptr] => Word
machine def zr_params_min(table)
  n = Machine.load64(table, 0)
  min = 0
  keyreq = 0
  i = 0
  while i < n
    kind = Machine.load64(table + 8 + (i * 16), 0)
    if kind == PARAM_REQ
      min += 1
    elsif kind == PARAM_KEYREQ
      keyreq = 1
    end
    i += 1
  end
  min + keyreq
end

sig [Ptr] => Bool
machine def zr_params_rest_p(table)
  n = Machine.load64(table, 0)
  i = 0
  while i < n
    if Machine.load64(table + 8 + (i * 16), 0) == PARAM_REST
      return true
    end
    i += 1
  end
  false
end

# `Proc#arity`. For a lambda, it is the method arity. For a plain proc,
# it is the required count, or -(count + 1) only when it has a rest
# parameter.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_arity(recv, argc, argv, cref, blk)
  meta = RProc.meta(recv)
  if meta == 0
    if RProc.fn(recv) == Machine.addr(:zr_method_block)
      return zr_fix(zr_method_arity_of(RProc.self(recv)))
    end
    return zr_fix(0 - 2)
  end
  if RProc.lambda(recv) != 0
    return zr_fix(FrameMeta.arity(meta))
  end
  min = zr_params_min(FrameMeta.params(meta))
  zr_fix(zr_params_rest_p(FrameMeta.params(meta)) ? 0 - min - 1 : min)
end

sig [Value, Value] => Value
machine def zr_proc_param_rows(recv, lenient)
  meta = RProc.meta(recv)
  if meta == 0
    if RProc.fn(recv) == Machine.addr(:zr_method_block)
      return zr_method_rows(RProc.self(recv))
    end
    out = zr_ary_new(2)
    row = zr_ary_new(1)
    zr_ary_push(row, zr_sym(Machine.id(:req)))
    zr_ary_push(out, row)
    row = zr_ary_new(1)
    zr_ary_push(row, zr_sym(Machine.id(:rest)))
    zr_ary_push(out, row)
    return out
  end
  zr_param_rows(FrameMeta.params(meta), lenient != QFALSE)
end

sig [Word] => Word
machine def zr_param_kind_name(kind)
  if kind == PARAM_REQ
    Machine.id(:req)
  elsif kind == PARAM_OPT
    Machine.id(:opt)
  elsif kind == PARAM_REST
    Machine.id(:rest)
  elsif kind == PARAM_KEYREQ
    Machine.id(:keyreq)
  elsif kind == PARAM_KEY
    Machine.id(:key)
  elsif kind == PARAM_KEYREST
    Machine.id(:keyrest)
  elsif kind == PARAM_NOKEY
    Machine.id(:nokey)
  else
    Machine.id(:block)
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_owner_m(recv, argc, argv, cref, blk)
  RMethod.owner(recv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_receiver(recv, argc, argv, cref, blk)
  RMethod.recv(recv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_name(recv, argc, argv, cref, blk)
  zr_sym(MEntry.mid(RMethod.entry(recv)))
end

# The name in the method's definition. For an alias, it is the name of
# the original def.
sig [Ptr] => Word
machine def zr_method_original_id(e)
  if MEntry.kind(e) == KIND_DEF
    return FrameMeta.name(MEntry.meta(e))
  end
  MEntry.orig(e)
end

# The module where the entry was defined: for an alias, the source of
# the alias; if not, the method's owner.
sig [Value] => Value
machine def zr_method_defined_in(m)
  e = RMethod.entry(m)
  if MEntry.kind(e) == KIND_DEF && MEntry.meta(e) != 0 && FrameMeta.owner(MEntry.meta(e)) != QNIL
    owner = FrameMeta.owner(MEntry.meta(e))
    return zr_type(owner) == T_ICLASS ? RClass.attached(owner) : owner
  end
  RMethod.owner(m)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_original_name(recv, argc, argv, cref, blk)
  zr_sym(zr_method_original_id(RMethod.entry(recv)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_unbind(recv, argc, argv, cref, blk)
  m = zr_alloc(T_METHOD, zr_global(G_UNBOUND_METHOD), RMethod.size)
  RMethod.set_recv(m, Machine.value(QUNDEF))
  RMethod.set_klass(m, RMethod.klass(recv))
  RMethod.set_owner(m, RMethod.owner(recv))
  zr_memcpy(RMethod.entry(m), RMethod.entry(recv), MEntry.size)
  m
end

# `bind(obj)`: the receiver must be an instance of the owner class. A
# module's method binds to any object.
sig [Value, Value] => Value
machine def zr_method_bind_to(m, obj)
  owner = RMethod.owner(m)
  if zr_type(owner) != T_MODULE && !zr_is_a(obj, owner)
    if zr_singleton_p(owner)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("singleton method called for a different object"), 46)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("bind argument must be an instance of "), 37)
    zr_buf_class(b, owner)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  bound = zr_alloc(T_METHOD, zr_global(G_METHOD), RMethod.size)
  RMethod.set_recv(bound, obj)
  RMethod.set_klass(bound, zr_class_of(obj))
  RMethod.set_owner(bound, owner)
  zr_memcpy(RMethod.entry(bound), RMethod.entry(m), MEntry.size)
  bound
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_bind(recv, argc, argv, cref, blk)
  zr_method_bind_to(recv, Machine.value(Machine.load64(argv, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_bind_call(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_wrong_arity_min(0, 1)
  end
  bound = zr_method_bind_to(recv, Machine.value(Machine.load64(argv, 0)))
  return bound if bound == QUNDEF
  zr_method_invoke(bound, argc - 1, argv + 8, blk)
end

# Returns the FrameMeta that gives the location of a method entry in a
# Ruby file, or 0. A def or a block uses its own FrameMeta, and an
# attribute uses the class body's. A core method has no file in its
# FrameMeta, so reflection treats it as a builtin: no location, and the
# arity and parameters of a C method.
sig [Ptr] => Ptr
machine def zr_method_location(e)
  meta = zr_method_meta(e)
  if meta == 0 && (MEntry.kind(e) == KIND_ATTR_READER || MEntry.kind(e) == KIND_ATTR_WRITER) && FrameMeta.file_len(MEntry.meta(e)) > 0
    meta = MEntry.meta(e)
  end
  if meta != 0 && FrameMeta.file_len(meta) == 0
    return 0
  end
  meta
end

sig [Value, Word, Ptr, Value, Value] => Value
# Returns the box that contains the method's compiled body. Returns nil
# for a runtime method, or for a method written where no box was open.
sig [Value] => Value
machine def zr_method_box_m(m)
  meta = zr_method_location(RMethod.entry(m))
  if meta == 0 || Machine.word(FrameMeta.box(meta)) == 0
    return Machine.value(QNIL)
  end
  FrameMeta.box(meta)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_source_location(recv, argc, argv, cref, blk)
  e = RMethod.entry(recv)
  meta = zr_method_location(e)
  if meta == 0
    # A method of the core: the def of the ones that CRuby writes in Ruby.
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(recv))
    return zr_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:builtin_source), 1, arg)
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta)))
  zr_ary_push(out, zr_fix(FrameMeta.line(meta)))
  out
end

# Two methods are equal when they refer to the same code, with the same
# receiver and the same owner.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_METHOD || zr_class_of(other) != zr_class_of(recv)
    return Machine.value(QFALSE)
  end
  a = RMethod.entry(recv)
  b = RMethod.entry(other)
  # A method from `define_method` keeps its body in the entry's cref.
  # Two different bodies are two different methods.
  zr_bool(RMethod.recv(recv) == RMethod.recv(other) && RMethod.owner(recv) == RMethod.owner(other) && zr_entry_body(a) == zr_entry_body(b) && MEntry.kind(a) == MEntry.kind(b) &&
          (MEntry.kind(a) != KIND_BMETHOD || MEntry.cref(a) == MEntry.cref(b)))
end

# The hash of the parts that `zr_method_eq` compares, so that equal
# methods have the same hash. As in method_hash, it uses the receiver
# and the entry.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_hash(recv, argc, argv, cref, blk)
  e = RMethod.entry(recv)
  h = zr_hash_mix(Machine.word(RMethod.recv(recv)))
  h = zr_hash_mix(h ^ Machine.word(RMethod.owner(recv)))
  h = zr_hash_mix(h ^ Machine.word(zr_entry_body(e)) ^ MEntry.kind(e))
  if MEntry.kind(e) == KIND_BMETHOD
    h = zr_hash_mix(h ^ Machine.word(MEntry.cref(e)))
  end
  zr_fix(h & 4611686018427387903)
end

# Writes one parameter entry as `inspect` shows it in CRuby: `a`,
# `b=...`, `*r`, `k:`, `o: ...`, `**kw`, `&blk`, `**nil`. An unnamed
# entry is `_`, `*` or `**`. An anonymous block is `...`, which also
# represents the full `(*, **, &)` triple (`forwarding`). An anonymous
# `**` after another entry writes nothing, and removes the separator
# before it.
sig [Ptr, Word, Word, Word, Bool] => Void
machine def zr_buf_param(b, kind, id, i, forwarding)
  if kind == PARAM_REST
    if id == Machine.id(:*)
      zr_buf_push(b, forwarding ? Machine.bytes("...") : Machine.bytes("*"), forwarding ? 3 : 1)
    else
      zr_buf_byte(b, 42)
      zr_buf_sym(b, id)
    end
  elsif kind == PARAM_KEYREST
    if id != Machine.id(:**)
      zr_buf_push(b, Machine.bytes("**"), 2)
      zr_buf_sym(b, id)
    elsif i > 0
      Buf.set_len(b, Buf.len(b) - 2)
    else
      zr_buf_push(b, Machine.bytes("**"), 2)
    end
  elsif kind == PARAM_BLOCK
    if id != Machine.id(:&)
      zr_buf_byte(b, 38)
      zr_buf_sym(b, id)
    elsif forwarding
      Buf.set_len(b, Buf.len(b) - 2)
    else
      zr_buf_push(b, Machine.bytes("..."), 3)
    end
  elsif kind == PARAM_NOKEY
    zr_buf_push(b, Machine.bytes("**nil"), 5)
  else
    if id != 0
      zr_buf_sym(b, id)
    else
      zr_buf_byte(b, 95)
    end
    if kind == PARAM_OPT
      zr_buf_push(b, Machine.bytes("=..."), 4)
    elsif kind == PARAM_KEYREQ
      zr_buf_byte(b, 58)
    elsif kind == PARAM_KEY
      zr_buf_push(b, Machine.bytes(": ..."), 5)
    end
  end
end

# Whether the table is the `(*, **, &)` of a `(...)` parameter list.
sig [Ptr] => Bool
machine def zr_params_forwarding_p(table)
  Machine.load64(table, 0) == 3 &&
    Machine.load64(table + 8, 0) == PARAM_REST && Machine.load64(table + 16, 0) == Machine.id(:*) &&
    Machine.load64(table + 24, 0) == PARAM_KEYREST && Machine.load64(table + 32, 0) == Machine.id(:**) &&
    Machine.load64(table + 40, 0) == PARAM_BLOCK && Machine.load64(table + 48, 0) == Machine.id(:&)
end

sig [Ptr, Value] => Void
machine def zr_buf_method_params(b, m)
  e = RMethod.entry(m)
  meta = zr_method_meta(e)
  if meta == 0 || FrameMeta.file_len(meta) == 0
    # A core method: the list that `parameters` gives, which knows the
    # ones CRuby writes in Ruby.
    params = zr_send(m, Machine.id(:parameters), 0, 0)
    if params != QUNDEF
      arg = Machine.slot(8)
      Machine.store64(arg, 0, Machine.word(params))
      shown = zr_send(zr_core_class(Machine.id(:Method)), Machine.id(:params_shown), 1, arg)
      if shown != QUNDEF
        zr_buf_str(b, shown)
        return
      end
    end
    Task.set_pending(zr_task(), Machine.value(QNIL))
  end
  zr_buf_byte(b, 40)
  arity = zr_method_arity_of(m)
  if meta != 0 && FrameMeta.file_len(meta) > 0
    table = FrameMeta.params(meta)
    n = Machine.load64(table, 0)
    forwarding = zr_params_forwarding_p(table)
    i = 0
    while i < n
      if i > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      zr_buf_param(b, Machine.load64(table + 8 + (i * 16), 0), Machine.load64(table + 16 + (i * 16), 0), i, forwarding)
      i += 1
    end
  elsif arity < 0
    zr_buf_byte(b, 42)
  else
    i = 0
    while i < arity
      if i > 0
        zr_buf_push(b, Machine.bytes(", "), 2)
      end
      zr_buf_byte(b, 95)
      i += 1
    end
  end
  zr_buf_byte(b, 41)
end

# `#<Method: C#name(params) file:line>`. A singleton method shows its
# object and a dot. A method found in an ancestor of the lookup class
# shows the owner in parentheses. An UnboundMethod shows only the owner.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_method_inspect(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("#<"), 2)
  zr_buf_class(b, zr_class_of(recv))
  zr_buf_push(b, Machine.bytes(": "), 2)
  owner = RMethod.owner(recv)
  klass = RMethod.klass(recv)
  if zr_singleton_p(owner)
    attached = RClass.attached(owner)
    if RMethod.recv(recv) == QUNDEF || RMethod.recv(recv) == attached
      s = zr_inspect(RMethod.recv(recv) == QUNDEF ? owner : attached)
      return s if s == QUNDEF
      zr_buf_str(b, s)
    else
      s = zr_inspect(RMethod.recv(recv))
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_byte(b, 40)
      s = zr_inspect(attached)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_byte(b, 41)
    end
    zr_buf_byte(b, RMethod.recv(recv) == QUNDEF ? 35 : 46)
  else
    while zr_singleton_p(klass) || zr_type(klass) == T_ICLASS
      klass = RClass.superclass(klass)
    end
    defined = zr_method_defined_in(recv)
    if RMethod.recv(recv) == QUNDEF
      klass = defined
    end
    s = zr_inspect(klass)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    if klass != defined
      zr_buf_byte(b, 40)
      s = zr_inspect(defined)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_byte(b, 41)
    end
    zr_buf_byte(b, 35)
  end
  e = RMethod.entry(recv)
  zr_buf_sym(b, MEntry.mid(e))
  original = zr_method_original_id(e)
  if original != MEntry.mid(e)
    zr_buf_byte(b, 40)
    zr_buf_sym(b, original)
    zr_buf_byte(b, 41)
  end
  zr_buf_method_params(b, recv)
  meta = zr_method_location(e)
  if meta != 0
    zr_buf_byte(b, 32)
    zr_buf_push(b, FrameMeta.file(meta), FrameMeta.file_len(meta))
    zr_buf_byte(b, 58)
    zr_buf_long(b, FrameMeta.line(meta))
  else
    # A core method that CRuby writes in Ruby shows its builtin def.
    place = zr_method_source_location(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
    return place if place == QUNDEF
    if place != QNIL
      zr_buf_byte(b, 32)
      zr_buf_str(b, zr_ary_at(place, 0))
      zr_buf_byte(b, 58)
      zr_buf_long(b, zr_fix2long(zr_ary_at(place, 1)))
    end
  end
  zr_buf_byte(b, 62)
  zr_buf_take_at(b, ENC_BINARY)
end
