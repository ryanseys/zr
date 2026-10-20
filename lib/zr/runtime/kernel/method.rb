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
  PARAM_NOBLOCK = 8

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

  # The class or module among the ancestors of `klass` whose table holds
  # the entry `e`, or nil.
  #: (value, ptr) -> value
  def zr_entry_holder(klass, e)
    k = klass
    while k != QNIL
      if zr_find_method_at(k, MEntry[e].mid) == e
        return zr_type(k) == T_ICLASS ? RClass[k].attached : k
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
    e = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
    zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
    zr_exc_detail(e, Machine.id(:receiver), klass)
    zr_exc_raise(e)
  end

  # Returns the Method (with a receiver) or the UnboundMethod (`recv` is
  # undef) for `mid` on `klass`, or raises the NameError.
  #: (value, value, word) -> value
  def zr_method_new(recv, klass, mid)
    e = zr_find_method(klass, mid)
    # A visibility copy with no method above it names nothing.
    if e != 0 && MEntry[e].kind == KIND_MISSING
      e = Machine.ptr(0)
    end
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
    zr_method_made(recv, klass, owner, e)
  end

  # The Method (or UnboundMethod) for entry `e`, which the last lookup
  # found at Task.found: its class is that node, or for a refinement's
  # method, the node of the refined module or the refined class.
  #: (value, ptr) -> value
  def zr_method_at_found(recv, e)
    found = Task[zr_task()].found
    h = zr_refinement_holder(found)
    if h != QNIL
      klass = zr_type(found) == T_ICLASS ? RClass[found].superclass : ClassExt[RClass[h].ext].refined
      return zr_method_made(recv, klass, h, e)
    end
    zr_method_made(recv, found, zr_type(found) == T_ICLASS ? RClass[found].attached : found, e)
  end

  #: (value, value, value, ptr) -> value
  def zr_method_made(recv, klass, owner, e)
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
    MEntry[e].body = 0
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
    e = Machine.ptr(RMethod[m].entry)
    found = zr_find_method(RMethod[m].klass, RMethod[m].entry.mid)
    # A module's method bound to a class that does not include the module
    # is not what the lookup finds: its `super` starts from its owner. So
    # does a method that the lookup finds only as a subclass's visibility
    # copy of it.
    if found == 0 || MEntry[found].meta != MEntry[e].meta || MEntry[found].cref != MEntry[e].cref || MEntry[found].from != MEntry[e].from
      Task[zr_task()].found = zr_method_super_start(m, e)
    end
    # A C method that the program calls through a Method fires :c_call
    # and :c_return, as vm_call0 fires them under Method#call.
    top = Task[zr_task()].top
    if zr_trace_sends_p() && zr_trace_c_entry_p(e) && top != 0 && zr_trace_program_frame_p(Frame[top].prev)
      return zr_trace_send_invoke(e, RMethod[m].recv, MEntry[e].mid, argc, argv, blk, zr_kw_take(), TRACE_C_CALL)
    end
    zr_invoke(e, RMethod[m].recv, argc, argv, blk, zr_kw_take_lent())
  end

  # A send that a core method makes for the program that called it, as
  # rb_funcall makes it in C: Class#new sends `initialize`, include sends
  # `append_features`, and the hooks. A C method that it reaches fires
  # :c_call and :c_return, as vm_call0 fires them, when the program
  # called the core method.
  #: (value, word, word, ptr, value) -> value
  def zr_send_for_caller(recv, mid, argc, argv, blk)
    top = Task[zr_task()].top
    rec = top
    # The core's frames have no file. Eval support's own code (the
    # compiler) has one, and is not the program: its calls fire nothing.
    while rec != 0 && (Frame[rec].meta == 0 || FrameMeta[Frame[rec].meta].file_len == 0)
      rec = Frame[rec].prev
    end
    # With the program's frame on top, the send fires the events itself.
    if zr_trace_sends_p() && rec != top && rec != 0 && zr_trace_program_frame_p(rec)
      e = zr_find_method(zr_box_view(zr_class_of(recv)), mid)
      if e != 0 && zr_trace_c_entry_p(e)
        return zr_trace_send_invoke(e, recv, mid, argc, argv, blk, zr_kw_take(), TRACE_C_CALL)
      end
    end
    zr_send_blk(recv, mid, argc, argv, blk)
  end

  # `Primitive.zr_funcall_m(recv, name, arg)`: the core's send of one
  # argument by name, as rb_funcall makes it (zr_send_for_caller).
  #: (value, value, value) -> value
  def zr_funcall_m(recv, name, arg)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(arg))
    zr_send_for_caller(recv, zr_sym2id(name), 1, slot, Machine.value(QNIL))
  end

  # Where `super` in a Method's body starts: its owner, except for a
  # refinement's method, whose owner is the refined class once bound. Its
  # `super` finds the method that the refinement overrides.
  #: (value, ptr) -> value
  def zr_method_super_start(m, e)
    meta = zr_method_meta(e)
    if meta != 0
      defined = FrameMeta[meta].owner
      if !zr_special_p(defined) && zr_type(defined) == T_MODULE && ClassExt[RClass[defined].ext].refined != QNIL
        # A module's refinement goes on from the module's node in the
        # Method's class.
        node = zr_refined_node(RMethod[m].klass, defined)
        return zr_type(node) == T_ICLASS ? zr_refinement_iclass(node, defined) : defined
      end
    end
    # A Method whose lookup started below an include node of its owner
    # (one that super_method made) goes on from the first such node, also
    # when the module is in the list more than once.
    k = RMethod[m].klass
    while !zr_special_p(k) && k != QNIL
      if zr_type(k) == T_ICLASS && RClass[k].attached == RMethod[m].owner
        at = zr_find_method_at(k, MEntry[e].mid)
        if at != 0 && MEntry[at].meta == MEntry[e].meta
          return k
        end
        break
      end
      k = RClass[k].superclass
    end
    RMethod[m].owner
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

  # `Kernel.plain_require?`: whether the `require` that `recv` finds is
  # ruby's own (a core entry) or the body of `standard`, an UnboundMethod
  # of rubygems' Kernel#require (nil before rubygems loads). A `require`
  # that the program undefined counts as ruby's own. So does any require
  # of code that the program does not see (eval support's compiler and
  # what it loads), which ruby does not have. Any other require searches
  # when `off` is true: its file is in a directory that the program took
  # off $LOAD_PATH.
  #: (value, value, value) -> value
  def zr_plain_require_p_m(recv, standard, off)
    if zr_hidden_now()
      return Machine.value(QTRUE)
    end
    if off == QTRUE
      return Machine.value(QFALSE)
    end
    e = zr_find_method(zr_class_of(recv), Machine.id(:require))
    if e == 0 || MEntry[e].core != 0 || MEntry[e].kind == KIND_UNDEF
      return Machine.value(QTRUE)
    end
    meta = zr_method_meta(e)
    if standard != QNIL && meta != 0 && meta == zr_method_meta(Machine.ptr(RMethod[standard].entry))
      return Machine.value(QTRUE)
    end
    Machine.value(QFALSE)
  end

  # A compiled def has the arity of its parameters. A builtin's arity is
  # in its entry. A core def returns what C returns (-1 for any optional
  # count), unless CRuby also writes that method in Ruby.
  #: (value) -> word
  def zr_method_arity_of(m)
    e = Machine.ptr(RMethod[m].entry)
    walked = zr_walk_described(e, Machine.id(:__walk_arity__))
    if walked != QNIL
      return zr_fix2long(walked)
    end
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

  # A method that the tree walk defines (Zr::Eval::World.describe) is a
  # define_method of `|*args, **kwargs, &blk|`. Its body keeps the
  # parameters and the arity of the def that the string wrote, which
  # `parameters`, `arity` and `inspect` give in place of the block's.
  #: (value, value, value) -> value
  def zr_walk_describe_m(m, rows, arity)
    e = Machine.ptr(RMethod[m].entry)
    if MEntry[e].kind == KIND_BMETHOD
      zr_state_set(MEntry[e].cref, zr_sym(Machine.id(:__walk_rows__)), rows)
      zr_state_set(MEntry[e].cref, zr_sym(Machine.id(:__walk_arity__)), arity)
    end
    Machine.value(QNIL)
  end

  # What `zr_walk_describe_m` kept as `id` for the method entry `e`, or nil.
  #: (ptr, word) -> value
  def zr_walk_described(e, id)
    if MEntry[e].kind != KIND_BMETHOD || zr_special_p(MEntry[e].cref)
      return Machine.value(QNIL)
    end
    zr_ivar_get(MEntry[e].cref, id)
  end

  #: (value) -> value
  def zr_method_rows(m)
    e = Machine.ptr(RMethod[m].entry)
    walked = zr_walk_described(e, Machine.id(:__walk_rows__))
    if walked != QNIL
      return zr_ary_subseq(walked, 0, RArray[walked].len)
    end
    # A method made from a Symbol's Proc (`define_method(:m, &:sym)`) has
    # that Proc's parameters, as its body is the Proc.
    if MEntry[e].kind == KIND_BMETHOD && RProc[MEntry[e].cref].fn == Machine.addr(:zr_symbol_block)
      return zr_proc_param_rows(MEntry[e].cref, Machine.value(QFALSE))
    end
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
      if RProc[recv].fn == Machine.addr(:zr_symbol_block)
        return zr_fix(0 - 2)
      end
      # collect_i takes the arity of the program's block
      # (rb_block_min_max_arity); the other iterators of the core are
      # ifuncs of any arity.
      if RProc[recv].fn == Machine.addr(:zr_enum_collect_block)
        return zr_proc_arity(zr_ary_at(RProc[recv].self, 1), 0, argv, cref, blk)
      end
      return zr_fix(0 - 1)
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
    elsif kind == PARAM_NOBLOCK
      Machine.id(:noblock)
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
    # A refinement's method binds to an instance of the class it refines,
    # which is then its owner.
    if zr_type(owner) == T_MODULE && ClassExt[RClass[owner].ext].refined != QNIL
      owner = ClassExt[RClass[owner].ext].refined
    end
    if zr_type(owner) != T_MODULE && !zr_is_a(obj, owner) && !zr_core_binds_copy(owner, obj)
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
    # convert_umethod_to_method_components: a module's method is bound at
    # the module's node in the object's ancestors, or at the module when
    # the object does not include it.
    RMethod[bound].klass = zr_type(owner) == T_MODULE ? zr_owner_node(zr_class_of(obj), owner) : zr_class_of(obj)
    RMethod[bound].owner = owner
    zr_memcpy(Machine.ptr(RMethod[bound].entry), Machine.ptr(RMethod[m].entry), MEntry.size)
    bound
  end

  # Whether the core's own code binds a method of the builtin class
  # `owner` to `obj`, an instance of a copy of that class (`String.clone`).
  # The object has the builtin type of the class, which is all that
  # CRuby's C function needs; a program's own bind still raises.
  #: (value, value) -> bool
  def zr_core_binds_copy(owner, obj)
    kind = zr_alloc_kind(owner)
    if kind == ALLOC_OBJECT || zr_special_p(obj) || zr_alloc_kind(zr_class_of(obj)) != kind
      return false
    end
    caller = Frame[Task[zr_task()].top].prev
    caller != 0 && FrameMeta[Frame[caller].meta].file_len == 0
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
    zr_ary_push(out, zr_meta_path(meta))
    zr_ary_push(out, zr_fix(FrameMeta[meta].line))
    out
  end

  # Two methods are equal when they refer to the same code, with the same
  # receiver, and one owner is the other or an ancestor of it: an alias
  # or a visibility change in a subclass or a singleton class is the same
  # method, as CRuby resolves the entry to its original.
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
    zr_bool(RMethod[recv].recv == RMethod[other].recv && zr_owners_related(RMethod[recv].owner, RMethod[other].owner) && zr_method_identity(a) == zr_method_identity(b) && (MEntry[a].body != 0 || MEntry[a].kind == MEntry[b].kind) &&
            (MEntry[a].kind != KIND_BMETHOD || MEntry[a].cref == MEntry[b].cref) &&
            # method_missing answers each name on its own.
            (MEntry[a].kind != KIND_MISSING || MEntry[a].mid == MEntry[b].mid))
  end

  # What makes two methods one for `==` and `hash`: rb_method_entry_eq
  # compares definitions, so an alias is its original, and two C methods
  # with one function are one. A core method that CRuby keeps apart from
  # its twin here, or joins to a method zr writes apart, has a body of its
  # own (zr_method_alias_of, zr_method_alone).
  #: (ptr) -> ptr
  def zr_method_identity(e)
    MEntry[e].body != 0 ? MEntry[e].body : zr_entry_body(e)
  end

  # In a core class body: `name` of `klass` is the same method as
  # `original`, as CRuby defines it with rb_define_alias or with the same
  # C function.
  #: (value, value, value) -> value
  def zr_method_alias_of(klass, name, original)
    e = zr_find_method_at(klass, zr_sym2id(name))
    o = zr_find_method_at(klass, zr_sym2id(original))
    if e != 0 && o != 0
      MEntry[o].body = zr_method_identity(o)
      MEntry[e].body = MEntry[o].body
    end
    Machine.value(QNIL)
  end

  # In a core class body: method `name` of `from` defined again on `to`,
  # private when `priv` is true, with the same code and `to` as its owner,
  # as CRuby defines one C function on two classes
  # (define_filetest_function). Its frames show `to`.
  #: (value, value, value, value) -> value
  def zr_method_share(from, name, to, priv)
    mid = zr_sym2id(name)
    e = zr_find_method_at(from, mid)
    if e != 0
      vis = VIS_PUBLIC
      if priv == QTRUE
        vis = VIS_PRIVATE
      end
      owned = zr_meta_owned(MEntry[e].meta, to)
      zr_method_copy(to, mid, e, owned, vis, false)
      MEntry[zr_find_method_at(zr_origin(to), mid)].label = owned
    end
    Machine.value(QNIL)
  end

  # In a core class body: alias `name` of `klass` shows its original's
  # name in a backtrace, as an alias that CRuby makes with
  # rb_define_alias or in its Ruby files does.
  #: (value, value) -> value
  def zr_method_label_original(klass, name)
    e = zr_find_method_at(klass, zr_sym2id(name))
    if e != 0
      MEntry[e].label = 0
    end
    Machine.value(QNIL)
  end

  # In a core class body: `name` of `klass`, which zr defines apart from
  # `original` where CRuby makes it an alias of `original`, shows the
  # original's name in a backtrace.
  #: (value, value, value) -> value
  def zr_method_label_as(klass, name, original)
    e = zr_find_method_at(klass, zr_sym2id(name))
    if e != 0 && MEntry[e].meta != 0
      label = zr_xmalloc(FrameMeta.size)
      zr_memcpy(label, MEntry[e].meta, FrameMeta.size)
      FrameMeta[label].name = zr_sym2id(original)
      MEntry[e].label = label
    end
    Machine.value(QNIL)
  end

  # The `core` word of a core alias that is == to its original but hashes
  # with its own name (zr_method_hash_apart).
  CORE_HASHED_APART = 2

  # In a core class body: `name` of `klass` is == to the method it aliases,
  # but has a hash of its own, as Kernel#yield_self (an alias in ruby's
  # kernel.rb) has beside then.
  #: (value, value) -> value
  def zr_method_hash_apart(klass, name)
    e = zr_find_method_at(klass, zr_sym2id(name))
    if e != 0
      MEntry[e].core = CORE_HASHED_APART
    end
    Machine.value(QNIL)
  end

  # In a core class body: `name` of `klass` is a method of its own, which
  # CRuby defines apart from the method that zr shares its code with.
  #: (value, value) -> value
  def zr_method_alone(klass, name)
    e = zr_find_method_at(klass, zr_sym2id(name))
    if e != 0
      MEntry[e].body = e
    end
    Machine.value(QNIL)
  end

  # Whether Method or UnboundMethod `m` is a define_method's, whose body
  # is a block that other methods may share.
  #: (value) -> value
  def zr_method_bmethod_p(m)
    zr_bool(MEntry[Machine.ptr(RMethod[m].entry)].kind == KIND_BMETHOD)
  end

  # Whether `a` is `b` or in its ancestor chain, or the other way round.
  #: (value, value) -> bool
  def zr_owners_related(a, b)
    zr_owner_below(a, b) || zr_owner_below(b, a)
  end

  # Whether `top` is `k` or one of the classes above it.
  #: (value, value) -> bool
  def zr_owner_below(k, top)
    while k != QNIL && !zr_special_p(k)
      if k == top || (zr_type(k) == T_ICLASS && RClass[k].attached == top)
        return true
      end
      k = RClass[k].superclass
    end
    false
  end

  # The hash of the parts that `zr_method_eq` compares, so that equal
  # methods have the same hash. As in method_hash, it uses the receiver
  # and the entry, not the owner, which an equal method may differ in.
  #: (value, word, ptr, value, value) -> value
  def zr_method_hash(recv, argc, argv, cref, blk)
    e = Machine.ptr(RMethod[recv].entry)
    h = zr_hash_mix(Machine.word(RMethod[recv].recv))
    if MEntry[e].core == CORE_HASHED_APART
      h = zr_hash_mix(h ^ MEntry[e].mid)
    end
    # A body that the core table set is the whole identity; the kind of a
    # builtin and of its twin written in Ruby differ.
    h = zr_hash_mix(h ^ Machine.word(zr_method_identity(e)) ^ (MEntry[e].body != 0 ? 0 : MEntry[e].kind))
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
    elsif kind == PARAM_NOBLOCK
      zr_buf_push(b, Machine.bytes("&nil"), 4)
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
    if meta == 0 || FrameMeta[meta].file_len == 0 || zr_walk_described(e, Machine.id(:__walk_rows__)) != QNIL
      # A core method, or one that the tree walk defined: the list that
      # `parameters` gives, which knows the ones CRuby writes in Ruby and
      # the def that the walk ran.
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
    # rb_obj_class: a Method with a singleton class still shows its class.
    zr_buf_class(b, zr_real_class(recv))
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
      # method_inspect: a module's node (or a class's origin) shows as its
      # module (#22321). A metaclass (the singleton class of a class or a
      # module) shows as itself; the singleton class of any other object
      # shows as the class above it, past the modules it extends.
      if zr_type(klass) == T_ICLASS
        klass = RClass[klass].attached
      end
      if zr_singleton_p(klass)
        attached = RClass[klass].attached
        if zr_special_p(attached) || (zr_type(attached) != T_CLASS && zr_type(attached) != T_MODULE)
          klass = RClass[klass].superclass
          while zr_type(klass) == T_ICLASS
            klass = RClass[klass].superclass
          end
        end
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
