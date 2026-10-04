module Zr::Kern
  # Method and UnboundMethod contain a copy of the method entry, the
  # module where the lookup found it (`owner`), the class of the lookup
  # (`klass`), and the receiver. An UnboundMethod has no receiver.
  class RMethod < Layout
    attr_reader :basic #: RBasic
    attr_accessor :recv #: value
    attr_accessor :klass #: value
    attr_accessor :owner #: value
    attr_reader :entry #: MEntry
  end

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

  #: (value) -> void
  def zr_mark_method(m)
    zr_mark(RMethod[m].recv)
    zr_mark(RMethod[m].klass)
    zr_mark(RMethod[m].owner)
    zr_mark_entry(Machine.ptr(RMethod[m].entry))
  end

  # Returns the module in `klass`'s ancestor list whose own method table
  # has `mid`, or nil.
  #: (value, word) -> value
  def zr_method_owner(klass, mid)
    k = klass
    while k != QNIL
      e = zr_find_method_at(k, mid)
      if e != 0
        if MEntry[e].kind == KIND_UNDEF
          return Machine.value(QNIL)
        end
        if zr_type(k) == T_ICLASS
          return RClass[k].attached
        end
        return k
      end
      k = RClass[k].superclass
    end
    Machine.value(QNIL)
  end

  # Raises the NameError for `mid` on `klass`. When `vis` is public (no
  # such method), the message is `undefined method 'x' for class 'C'`. If
  # not, it is `method 'x' for class 'C' is private` or protected.
  #: (value, word, word) -> value
  def zr_undefined_method(klass, mid, vis)
    zr_undefined_method_in(klass, klass, mid, vis)
  end

  # The same NameError, which names `shown` in its message and keeps
  # `klass` as its receiver.
  #: (value, value, word, word) -> value
  def zr_undefined_method_in(klass, shown, mid, vis)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if vis == VIS_PUBLIC
      zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    else
      zr_buf_push(b, Machine.bytes("method '"), 8)
    end
    zr_buf_sym(b, mid)
    if zr_type(shown) == T_MODULE
      zr_buf_push(b, Machine.bytes("' for module '"), 14)
    else
      zr_buf_push(b, Machine.bytes("' for class '"), 13)
    end
    s = zr_inspect(shown)
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
  #: (value, value, word) -> value
  def zr_method_new(recv, klass, mid)
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
    RMethod[m].recv = recv
    RMethod[m].klass = klass
    RMethod[m].owner = owner
    zr_memcpy(Machine.ptr(RMethod[m].entry), e, MEntry.size)
    zr_write_barrier_all(m)
    m
  end

  # Makes a Method for a name that the receiver handles only through
  # `method_missing`. Its owner is the class of the lookup (the singleton
  # class if the receiver has one), and it takes any number of arguments.
  #: (value, value, word) -> value
  def zr_method_missing_new(recv, klass, mid)
    m = zr_alloc(T_METHOD, zr_global(G_METHOD), RMethod.size)
    RMethod[m].recv = recv
    RMethod[m].klass = klass
    RMethod[m].owner = klass
    e = Machine.ptr(RMethod[m].entry)
    MEntry[e].mid = mid
    MEntry[e].fn = 0
    MEntry[e].direct = 0
    MEntry[e].arity = 0 - 1
    MEntry[e].kind = KIND_MISSING
    MEntry[e].meta = 0
    MEntry[e].cref = Machine.value(QNIL)
    MEntry[e].vis = VIS_PUBLIC
    MEntry[e].orig = mid
    MEntry[e].from = Machine.value(QNIL)
    MEntry[e].core = 0
    MEntry[e].concealed = 0
    MEntry[e].ivar.index = 0
    zr_methods_changed()
    m
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    zr_method_new(recv, zr_box_view(zr_class_of(recv)), Machine.load64(slot, 0))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_instance_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    zr_method_new(Machine.value(QUNDEF), recv, Machine.load64(slot, 0))
  end

  # `public_method` and `public_instance_method`: the same as `method`
  # and `instance_method`, but only when the method is public.
  #: (value, value, word) -> value
  def zr_public_method_new(recv, klass, mid)
    # mnew_missing asks respond_to_missing? with include_all false.
    if recv != QUNDEF && zr_find_method(klass, mid) == 0
      r = zr_respond_to_missing(recv, mid, Machine.value(QFALSE))
      return r if r == QUNDEF
      if r == QTRUE
        return zr_method_missing_new(recv, klass, mid)
      end
      return zr_undefined_method(klass, mid, VIS_PUBLIC)
    end
    m = zr_method_new(recv, klass, mid)
    return m if m == QUNDEF
    vis = RMethod[m].entry.vis
    return m if vis == VIS_PUBLIC
    zr_undefined_method(klass, mid, vis)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_public_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    zr_public_method_new(recv, zr_box_view(zr_class_of(recv)), Machine.load64(slot, 0))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public_instance_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    zr_public_method_new(Machine.value(QUNDEF), recv, Machine.load64(slot, 0))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_call(recv, argc, argv, cref, blk)
    if blk != QNIL
      RProc[blk].passed = 1
    end
    zr_method_invoke(recv, argc, argv, blk)
  end

  # The block function of `Method#to_proc`: the Proc's self is the Method.
  #: (value, word, ptr, value) -> value
  def zr_method_block(p, argc, argv, blk)
    zr_method_invoke(RProc[p].self, argc, argv, blk)
  end

  # Calls the Method's entry on its receiver. The lookup finds the
  # ancestor that has the name, and `super` in the body continues from
  # that ancestor.
  #: (value, word, ptr, value) -> value
  def zr_method_invoke(m, argc, argv, blk)
    zr_find_method(RMethod[m].klass, RMethod[m].entry.mid)
    zr_invoke(Machine.ptr(RMethod[m].entry), RMethod[m].recv, argc, argv, blk, zr_kw_take())
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_to_proc(recv, argc, argv, cref, blk)
    zr_native_proc(Machine.addr(:zr_method_block), recv)
  end

  # Returns the FrameMeta that gives the parameters, arity and location of
  # a method entry: its own for a def, its block's for a `define_method`
  # body, and 0 for a builtin.
  #: (ptr) -> ptr
  def zr_method_meta(e)
    if MEntry[e].kind == KIND_DEF
      return MEntry[e].meta
    end
    if MEntry[e].kind == KIND_BMETHOD
      return RProc[MEntry[e].cref].meta
    end
    0
  end

  # A compiled def has the arity of its parameters. A builtin's arity is
  # in its entry. A core def returns what C returns (-1 for any optional
  # count), unless CRuby also writes that method in Ruby.
  #: (value) -> word
  def zr_method_arity_of(m)
    e = Machine.ptr(RMethod[m].entry)
    meta = zr_method_meta(e)
    if meta != 0
      if FrameMeta[meta].file_len == 0 && FrameMeta[meta].ruby == 0 && FrameMeta[meta].arity < 0
        return 0 - 1
      end
      return FrameMeta[meta].arity
    end
    MEntry[e].fn == Machine.addr(:zr_f_notimplement) ? 0 : MEntry[e].arity
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_arity(recv, argc, argv, cref, blk)
    zr_fix(zr_method_arity_of(recv))
  end

  # Returns the entries of a parameter table in the form that `parameters`
  # returns. For a plain proc, required parameters are optional.
  #: (ptr, bool) -> value
  def zr_param_rows(table, lenient)
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
  #: (word) -> value
  def zr_arity_rows(arity)
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

  #: (value) -> value
  def zr_method_rows(m)
    e = Machine.ptr(RMethod[m].entry)
    meta = zr_method_meta(e)
    # A core def returns what C returns, unless CRuby also writes that
    # method in Ruby. A define_method body, also in the core, returns its
    # block's table.
    if meta != 0 && (FrameMeta[meta].file_len > 0 || FrameMeta[meta].ruby != 0 || MEntry[e].kind == KIND_BMETHOD)
      return zr_param_rows(FrameMeta[meta].params, false)
    end
    # A struct writer calls its one parameter `_`, as ruby does.
    if MEntry[e].kind == KIND_STRUCT_ASET
      row = zr_ary_new(2)
      zr_ary_push(row, zr_sym(Machine.id(:req)))
      zr_ary_push(row, zr_sym(Machine.id(:_)))
      out = zr_ary_new(1)
      zr_ary_push(out, row)
      return out
    end
    zr_arity_rows(zr_method_arity_of(m))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_parameters(recv, argc, argv, cref, blk)
    zr_method_rows(recv)
  end

  # The required count of a parameter table (all required keywords count
  # as one), and whether the table takes any number of arguments.
  #: (ptr) -> word
  def zr_params_min(table)
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

  # The required and optional positional parameters of `table`.
  #: (ptr) -> word
  def zr_params_positional(table)
    n = Machine.load64(table, 0)
    count = 0
    i = 0
    while i < n
      kind = Machine.load64(table + 8 + (i * 16), 0)
      if kind == PARAM_REQ || kind == PARAM_OPT
        count += 1
      end
      i += 1
    end
    count
  end

  #: (ptr) -> bool
  def zr_params_rest_p(table)
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
  #: (value, word, ptr, value, value) -> value
  def zr_proc_arity(recv, argc, argv, cref, blk)
    meta = RProc[recv].meta
    if meta == 0
      if RProc[recv].fn == Machine.addr(:zr_method_block)
        return zr_fix(zr_method_arity_of(RProc[recv].self))
      end
      return zr_fix(0 - 2)
    end
    if RProc[recv].lambda != 0
      return zr_fix(FrameMeta[meta].arity)
    end
    min = zr_params_min(FrameMeta[meta].params)
    zr_fix(zr_params_rest_p(FrameMeta[meta].params) ? 0 - min - 1 : min)
  end

  #: (value, value) -> value
  def zr_proc_param_rows(recv, lenient)
    meta = RProc[recv].meta
    if meta == 0
      if RProc[recv].fn == Machine.addr(:zr_method_block)
        return zr_method_rows(RProc[recv].self)
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
    zr_param_rows(FrameMeta[meta].params, lenient != QFALSE)
  end

  #: (word) -> word
  def zr_param_kind_name(kind)
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

  #: (value, word, ptr, value, value) -> value
  def zr_method_owner_m(recv, argc, argv, cref, blk)
    RMethod[recv].owner
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_receiver(recv, argc, argv, cref, blk)
    RMethod[recv].recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_name(recv, argc, argv, cref, blk)
    zr_sym(RMethod[recv].entry.mid)
  end

  # The name in the method's definition. For an alias, it is the name of
  # the original def.
  #: (ptr) -> word
  def zr_method_original_id(e)
    if MEntry[e].kind == KIND_DEF
      return FrameMeta[MEntry[e].meta].name
    end
    MEntry[e].orig
  end

  # The module where the entry was defined: for an alias, the source of
  # the alias; if not, the method's owner.
  #: (value) -> value
  def zr_method_defined_in(m)
    e = Machine.ptr(RMethod[m].entry)
    if MEntry[e].kind == KIND_DEF && MEntry[e].meta != 0 && FrameMeta[MEntry[e].meta].owner != QNIL
      owner = FrameMeta[MEntry[e].meta].owner
      return zr_type(owner) == T_ICLASS ? RClass[owner].attached : owner
    end
    RMethod[m].owner
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_original_name(recv, argc, argv, cref, blk)
    zr_sym(zr_method_original_id(Machine.ptr(RMethod[recv].entry)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_unbind(recv, argc, argv, cref, blk)
    m = zr_alloc(T_METHOD, zr_global(G_UNBOUND_METHOD), RMethod.size)
    RMethod[m].recv = Machine.value(QUNDEF)
    RMethod[m].klass = RMethod[recv].klass
    RMethod[m].owner = RMethod[recv].owner
    zr_memcpy(Machine.ptr(RMethod[m].entry), Machine.ptr(RMethod[recv].entry), MEntry.size)
    m
  end

  # `bind(obj)`: the receiver must be an instance of the owner class. A
  # module's method binds to any object.
  #: (value, value) -> value
  def zr_method_bind_to(m, obj)
    owner = RMethod[m].owner
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
    RMethod[bound].recv = obj
    RMethod[bound].klass = zr_class_of(obj)
    RMethod[bound].owner = owner
    zr_memcpy(Machine.ptr(RMethod[bound].entry), Machine.ptr(RMethod[m].entry), MEntry.size)
    bound
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_bind(recv, argc, argv, cref, blk)
    zr_method_bind_to(recv, Machine.value(Machine.load64(argv, 0)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_bind_call(recv, argc, argv, cref, blk)
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
  #: (ptr) -> ptr
  def zr_method_location(e)
    meta = zr_method_meta(e)
    if meta == 0 && (MEntry[e].kind == KIND_ATTR_READER || MEntry[e].kind == KIND_ATTR_WRITER) && FrameMeta[MEntry[e].meta].file_len > 0
      meta = MEntry[e].meta
    end
    if meta != 0 && FrameMeta[meta].file_len == 0
      return 0
    end
    meta
  end

  # Returns the box that contains the method's compiled body. Returns nil
  # for a runtime method, or for a method written where no box was open.
  #: (value) -> value
  def zr_method_box_m(m)
    meta = zr_method_location(Machine.ptr(RMethod[m].entry))
    if meta == 0 || Machine.word(FrameMeta[meta].box) == 0
      return Machine.value(QNIL)
    end
    FrameMeta[meta].box
  end

  #: (value, word, ptr, value, value) -> value
  def zr_method_source_location(recv, argc, argv, cref, blk)
    e = Machine.ptr(RMethod[recv].entry)
    meta = zr_method_location(e)
    if meta == 0
      # A method of the core: the def of the ones that CRuby writes in Ruby.
      arg = Machine.slot(8)
      Machine.store64(arg, 0, Machine.word(recv))
      return zr_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:builtin_source), 1, arg)
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_meta_file(meta))
    zr_ary_push(out, zr_fix(FrameMeta[meta].line))
    out
  end

  # Two methods are equal when they refer to the same code, with the same
  # receiver and the same owner.
  #: (value, word, ptr, value, value) -> value
  def zr_method_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_METHOD || zr_class_of(other) != zr_class_of(recv)
      return Machine.value(QFALSE)
    end
    a = Machine.ptr(RMethod[recv].entry)
    b = Machine.ptr(RMethod[other].entry)
    # A method from `define_method` keeps its body in the entry's cref.
    # Two different bodies are two different methods.
    zr_bool(RMethod[recv].recv == RMethod[other].recv && RMethod[recv].owner == RMethod[other].owner && zr_entry_body(a) == zr_entry_body(b) && MEntry[a].kind == MEntry[b].kind &&
            (MEntry[a].kind != KIND_BMETHOD || MEntry[a].cref == MEntry[b].cref))
  end

  # The hash of the parts that `zr_method_eq` compares, so that equal
  # methods have the same hash. As in method_hash, it uses the receiver
  # and the entry.
  #: (value, word, ptr, value, value) -> value
  def zr_method_hash(recv, argc, argv, cref, blk)
    e = Machine.ptr(RMethod[recv].entry)
    h = zr_hash_mix(Machine.word(RMethod[recv].recv))
    h = zr_hash_mix(h ^ Machine.word(RMethod[recv].owner))
    h = zr_hash_mix(h ^ Machine.word(zr_entry_body(e)) ^ MEntry[e].kind)
    if MEntry[e].kind == KIND_BMETHOD
      h = zr_hash_mix(h ^ Machine.word(MEntry[e].cref))
    end
    zr_fix(h & 4611686018427387903)
  end

  # Writes one parameter entry as `inspect` shows it in CRuby: `a`,
  # `b=...`, `*r`, `k:`, `o: ...`, `**kw`, `&blk`, `**nil`. An unnamed
  # entry is `_`, `*` or `**`. An anonymous block is `...`, which also
  # represents the full `(*, **, &)` triple (`forwarding`). An anonymous
  # `**` after another entry writes nothing, and removes the separator
  # before it.
  #: (ptr, word, word, word, bool) -> void
  def zr_buf_param(b, kind, id, i, forwarding)
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
        Buf[b].len = Buf[b].len - 2
      else
        zr_buf_push(b, Machine.bytes("**"), 2)
      end
    elsif kind == PARAM_BLOCK
      if id != Machine.id(:&)
        zr_buf_byte(b, 38)
        zr_buf_sym(b, id)
      elsif forwarding
        Buf[b].len = Buf[b].len - 2
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
  #: (ptr) -> bool
  def zr_params_forwarding_p(table)
    Machine.load64(table, 0) == 3 &&
      Machine.load64(table + 8, 0) == PARAM_REST && Machine.load64(table + 16, 0) == Machine.id(:*) &&
      Machine.load64(table + 24, 0) == PARAM_KEYREST && Machine.load64(table + 32, 0) == Machine.id(:**) &&
      Machine.load64(table + 40, 0) == PARAM_BLOCK && Machine.load64(table + 48, 0) == Machine.id(:&)
  end

  #: (ptr, value) -> void
  def zr_buf_method_params(b, m)
    e = Machine.ptr(RMethod[m].entry)
    meta = zr_method_meta(e)
    if meta == 0 || FrameMeta[meta].file_len == 0
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
      Task[zr_task()].pending = Machine.value(QNIL)
    end
    zr_buf_byte(b, 40)
    arity = zr_method_arity_of(m)
    if meta != 0 && FrameMeta[meta].file_len > 0
      table = FrameMeta[meta].params
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
  #: (value, word, ptr, value, value) -> value
  def zr_method_inspect(recv, argc, argv, cref, blk)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("#<"), 2)
    zr_buf_class(b, zr_class_of(recv))
    zr_buf_push(b, Machine.bytes(": "), 2)
    owner = RMethod[recv].owner
    klass = RMethod[recv].klass
    if zr_singleton_p(owner)
      attached = RClass[owner].attached
      if RMethod[recv].recv == QUNDEF || RMethod[recv].recv == attached
        s = zr_inspect(RMethod[recv].recv == QUNDEF ? owner : attached)
        return s if s == QUNDEF
        zr_buf_str(b, s)
      else
        s = zr_inspect(RMethod[recv].recv)
        return s if s == QUNDEF
        zr_buf_str(b, s)
        zr_buf_byte(b, 40)
        s = zr_inspect(attached)
        return s if s == QUNDEF
        zr_buf_str(b, s)
        zr_buf_byte(b, 41)
      end
      zr_buf_byte(b, RMethod[recv].recv == QUNDEF ? 35 : 46)
    else
      # method_inspect: a metaclass (the singleton class of a class or a
      # module) shows as itself; the singleton class of any other object
      # shows as the class above it.
      if zr_singleton_p(klass)
        attached = RClass[klass].attached
        if zr_special_p(attached) || (zr_type(attached) != T_CLASS && zr_type(attached) != T_MODULE)
          klass = RClass[klass].superclass
        end
      end
      while zr_type(klass) == T_ICLASS
        klass = RClass[klass].superclass
      end
      defined = zr_method_defined_in(recv)
      if RMethod[recv].recv == QUNDEF
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
    e = Machine.ptr(RMethod[recv].entry)
    zr_buf_sym(b, MEntry[e].mid)
    original = zr_method_original_id(e)
    if original != MEntry[e].mid
      zr_buf_byte(b, 40)
      zr_buf_sym(b, original)
      zr_buf_byte(b, 41)
    end
    zr_buf_method_params(b, recv)
    meta = zr_method_location(e)
    if meta != 0
      zr_buf_byte(b, 32)
      zr_buf_push(b, FrameMeta[meta].file, FrameMeta[meta].file_len)
      zr_buf_byte(b, 58)
      zr_buf_long(b, FrameMeta[meta].line)
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
end
