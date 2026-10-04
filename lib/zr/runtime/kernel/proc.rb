module Zr::Kern
  # Blocks. A block literal is a function that takes its Proc, the
  # arguments and a block of its own. The Proc contains what the body needs
  # from the place where it was written: the captured locals (an Env),
  # self, the cref, the block of the method, and two homes with their
  # serials. One home is the frame that a `break` returns to (with the
  # number of the call site). The other is the method that a `return`
  # leaves. A `break` or `return` is a pending unwind, as `raise` is: the
  # pending kind of the task tells which.
  #
  # A block literal is not a Proc cell until some code keeps it. The send
  # that passes it writes a Proc image into a slot of its own frame record
  # (`make_block` in the lowering). The image has FL_STACK set and is
  # already marked, so the collector reads nothing through it: the frame
  # roots what it refers to. A kernel function that keeps a block after the
  # call (as a `&b` parameter, in a Binding, a Fiber, a Hash default, an
  # at_exit hook, a define_method body) calls `zr_block_proc` on it first,
  # so no cell points into a stack. A frame gives its serial when it makes
  # a block. Thus a descriptor's frame is different from a later frame at
  # the same address, as for a Proc.
  #
  # The Env of a method or a block starts in its frame record the same way:
  # an REnv image with FL_STACK set, whose `slots` are the local slots of
  # the record, which the frame roots. The first keeper of the frame's scope
  # (`zr_env_escape`: a Proc made from one of its blocks, a Binding, an
  # eval) copies the Env to a cell, parents first. It points the `slots` of
  # the image at the slots of the copy, and keeps the cell in `cell` and in
  # the env slot of the frame. After that, the frame and all its blocks
  # read and write the slots of the cell, and a second keeper gets the same
  # cell.
  class REnv < Layout
    attr_reader :basic #: RBasic
    attr_accessor :parent #: value
    attr_accessor :slots #: ptr
    attr_accessor :nslots #: word
    attr_accessor :names #: ptr
    attr_accessor :cell #: value
    attr_accessor :home #: ptr
  end

  class RProc < Layout
    attr_reader :basic #: RBasic
    attr_accessor :fn #: ptr
    attr_accessor :meta #: ptr
    attr_accessor :env #: value
    attr_accessor :self #: value
    attr_accessor :cref #: value
    attr_accessor :blk #: value
    attr_accessor :home #: ptr
    attr_accessor :serial #: word
    attr_accessor :site #: word
    attr_accessor :ret_home #: ptr
    attr_accessor :ret_serial #: word
    attr_accessor :spread #: word
    attr_accessor :lambda #: word
    attr_accessor :passed #: word
  end

  module Block
    #: (ptr, value, word, ptr, value) -> value
    def self.call(fn, v1, n, p, v2) = Machine.indirect
  end

  T_ENV = 26
  T_PROC = 27
  # The descriptor of a block literal in the frame record of the send that
  # passes it.
  FL_STACK = 1 << 9
  # A Proc from `Ractor.shareable_proc`: frozen, calls only what it copied,
  # and has no Binding that reaches its scope. A copy of it is an ordinary
  # Proc, so the copy does not get the bit.
  FL_ISOLATED = 1 << 13
  G_PROC = 28
  G_LOCAL_JUMP_ERROR = 29
  PENDING_RAISE = 0
  PENDING_BREAK = 1
  PENDING_RETURN = 2
  PENDING_THROW = 3

  #: (value, word, ptr) -> value
  def zr_env_new(parent, n, names)
    e = zr_alloc(T_ENV, Machine.value(QNIL), REnv.size)
    REnv[e].parent = parent
    REnv[e].nslots = n
    REnv[e].names = names
    slots = zr_xmalloc(n * 8)
    i = 0
    while i < n
      Machine.store64(slots + (i * 8), 0, QNIL)
      i += 1
    end
    REnv[e].slots = slots
    REnv[e].cell = Machine.value(QNIL)
    REnv[e].home = 0
    e
  end

  # Returns the Env `env` as a cell. A cell returns itself. A frame
  # record's image becomes a cell once, parents first, and after that its
  # frame reads and writes the slots of the cell.
  #: (value) -> value
  def zr_env_escape(env)
    if env == QNIL || (RBasic[env].flags & FL_STACK) == 0
      return env
    end
    if REnv[env].cell != QNIL
      return REnv[env].cell
    end
    parent = zr_env_escape(REnv[env].parent)
    n = REnv[env].nslots
    e = zr_env_new(parent, n, REnv[env].names)
    zr_memcpy(REnv[e].slots, REnv[env].slots, n * 8)
    # A `&b` parameter bound to the block it was given is a Proc on the
    # stack of its caller (Params#raw_block?). The cell lives longer than
    # that frame.
    i = 0
    while i < n
      v = Machine.value(Machine.load64(REnv[e].slots + (i * 8), 0))
      if !zr_special_p(v) && (RBasic[v].flags & FL_STACK) != 0 && zr_type(v) == T_PROC
        Machine.store64(REnv[e].slots + (i * 8), 0, Machine.word(zr_block_proc(v)))
      end
      i += 1
    end
    zr_write_barrier_all(e)
    REnv[env].slots = REnv[e].slots
    REnv[env].cell = e
    Machine.store64(REnv[env].home + Frame.size, 0, Machine.word(e))
    e
  end

  # Returns the Env that is `depth` parents up from `env`.
  #: (value, word) -> value
  def zr_env_up(env, depth)
    while depth > 0
      env = REnv[env].parent
      depth -= 1
    end
    env
  end

  #: (value, word) -> value
  def zr_env_get(env, i)
    Machine.value(Machine.load64(REnv[env].slots + (i * 8), 0))
  end

  # The write barrier for a store into the slots of an Env.
  #
  # A frame record's image has FL_STACK set and is in no arena, so the
  # barrier skips it. That is correct while the slots are the frame's own,
  # because each collection reads them as a root. After a keeper moves the
  # scope to a cell (`zr_env_escape`), the slots are the cell's. A minor
  # collection reaches them only through the cell, and stops at the cell
  # when it is old. So from then on the barrier applies to the cell, and a
  # store through the image records nothing.
  #
  # This is what `vm_env_write_slowpath` (vm_insnhelper.c:514 at 4.0.7)
  # does: it remembers `VM_ENV_ENVVAL(ep)`, which is the cell, never the
  # frame. A heap Env has QNIL in `cell` and is its own cell.
  #: (value, value) -> void
  def zr_env_barrier(env, v)
    cell = REnv[env].cell
    zr_write_barrier(cell == QNIL ? env : cell, v)
  end

  inline :zr_env_barrier

  #: (value, word, value) -> value
  def zr_env_set(env, i, v)
    Machine.store64(REnv[env].slots + (i * 8), 0, Machine.word(v))
    zr_env_barrier(env, v)
    v
  end

  #: (value) -> void
  def zr_mark_env(e)
    zr_mark(REnv[e].parent)
    n = REnv[e].nslots
    i = 0
    while i < n
      zr_mark(zr_env_get(e, i))
      i += 1
    end
  end

  #: (value) -> void
  def zr_mark_proc(p)
    zr_mark(RProc[p].env)
    zr_mark(RProc[p].self)
    zr_mark(RProc[p].cref)
    blk = RProc[p].blk
    if blk != QNIL && (RBasic[blk].flags & FL_STACK) != 0
      zr_bug(Machine.bytes("a Proc holds a block descriptor of a stack: a keeper missed zr_block_proc\n"), 75)
    end
    zr_mark(blk)
  end

  # Returns the self of a block.
  #: (value) -> value
  def zr_proc_self_m(p)
    RProc[p].self
  end

  # Returns the same block with a different self, which is what a Ractor
  # runs. The body of the block runs with the ractor as self, and no frame
  # is between the call and the body where a report would show one.
  #: (value, value) -> value
  def zr_proc_rebind_m(p, self_)
    RProc[p].self = self_
    p
  end

  # Returns the outer locals that a block uses, as Symbols. A Ractor
  # refuses a block that uses one, and gives their names. A block that
  # uses none has no table.
  #: (value) -> value
  def zr_proc_captures_m(p)
    out = zr_ary_new(4)
    table = zr_proc_captures_table(p)
    if table == 0
      return out
    end
    n = Machine.load64(table, 0)
    i = 0
    while i < n
      zr_ary_push(out, zr_sym(Machine.load64(table + 8 + (i * 16), 0)))
      i += 1
    end
    out
  end

  # Returns the same locals as `[name, written, rebound]` records: whether
  # the block writes the local, and whether the scope that owns it binds it
  # more than once. `Ractor.shareable_proc` refuses a block for either.
  #: (value) -> value
  def zr_proc_capture_rows_m(p)
    out = zr_ary_new(4)
    table = zr_proc_captures_table(p)
    if table == 0
      return out
    end
    n = Machine.load64(table, 0)
    i = 0
    while i < n
      row = table + 8 + (i * 16)
      flags = Machine.load64(row, 8)
      triple = zr_ary_new(3)
      zr_ary_push(triple, zr_sym(Machine.load64(row, 0)))
      zr_ary_push(triple, zr_bool((flags & 1) != 0))
      zr_ary_push(triple, zr_bool((flags & 2) != 0))
      zr_ary_push(out, triple)
      i += 1
    end
    out
  end

  # Returns a copy of `p` that any ractor can call, with `self_` as self.
  # A literal block becomes a lambda when `lambda` is true. A Proc that
  # was passed in keeps its kind, as ruby's `shareable_lambda(&pr)` does.
  #: (value, value, value) -> value
  def zr_proc_isolated_m(p, self_, lambda)
    copy = zr_copy_cell(p)
    if copy == QUNDEF
      return copy
    end
    RProc[copy].self = self_
    if lambda == QTRUE && RProc[p].passed == 0
      RProc[copy].lambda = 1
    end
    RBasic[copy].flags = RBasic[copy].flags | FL_FREEZE | FL_ISOLATED
    copy
  end

  # A native Proc has no meta, and no outer locals.
  #: (value) -> ptr
  def zr_proc_captures_table(p)
    meta = RProc[p].meta
    if meta == 0
      return 0
    end
    FrameMeta[meta].captures
  end

  # Returns a block as an object. A Proc is one already. A literal's
  # descriptor becomes a Proc in its own cell, its own block first, so a
  # Proc keeps no descriptor. When code keeps the same descriptor two
  # times, it makes two Procs.
  #: (value) -> value
  def zr_block_proc(b)
    if b == QNIL || (RBasic[b].flags & FL_STACK) == 0
      return b
    end
    blk = zr_block_proc(RProc[b].blk)
    env = zr_env_escape(RProc[b].env)
    # An adapter keeps a block as its self: the each adapter its block
    # (zr_enum_each), and the values adapter its inner block
    # (zr_enum_each_values). The block can be a stack image, so it goes to
    # the heap with the adapter.
    self_ = RProc[b].self
    if RProc[b].fn == Machine.addr(:zr_enum_each_block) || RProc[b].fn == Machine.addr(:zr_enum_values_block)
      self_ = zr_block_proc(self_)
    end
    p = zr_alloc(T_PROC, zr_global(G_PROC), RProc.size)
    zr_memcpy(Machine.ptr(p) + RBasic.size, Machine.ptr(b) + RBasic.size, RProc.size - RBasic.size)
    RProc[p].blk = blk
    RProc[p].env = env
    RProc[p].self = self_
    p
  end

  # `&:name`: a Proc that sends `name` to its first argument, as a call
  # with a receiver, so it cannot call a private method (the public call of
  # rb_sym_proc_call). The block function reads the Symbol from the self of
  # the Proc. A Proc made where refinements are active keeps their list in
  # its cref. Its send looks up the name under them wherever the Proc is
  # called, as ruby's refined Symbol#to_proc does.
  #: (value, word, ptr, value) -> value
  def zr_symbol_block(p, argc, argv, blk)
    if argc == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no receiver given"), 17)
    end
    if RProc[p].cref != QNIL
      t = zr_task()
      Task[t].refine = RProc[p].cref
      r = zr_dispatch(0, Machine.value(Machine.load64(argv, 0)), zr_sym2id(RProc[p].self), argc - 1, argv + 8, 2, blk)
      Task[t].refine = Machine.value(QNIL)
      return r
    end
    zr_dispatch(0, Machine.value(Machine.load64(argv, 0)), zr_sym2id(RProc[p].self), argc - 1, argv + 8, 2, blk)
  end

  # Returns the Proc of `sym` under the refinements that are active in the
  # task, or the shared Proc when none are active.
  #: (value) -> value
  def zr_sym_to_proc_here(sym)
    row = Task[zr_task()].refine
    if row == QNIL
      return zr_sym_to_proc(sym)
    end
    p = zr_native_proc(Machine.addr(:zr_symbol_block), sym)
    RProc[p].cref = row
    p
  end

  #: (value) -> value
  def zr_sym_to_proc(sym)
    # One lambda for each Symbol for the life of the program, as ruby's
    # rb_sym_to_proc returns. A table that the collector roots keeps them.
    table = zr_global(G_SYM_PROCS)
    if zr_special_p(table)
      table = zr_hash_new()
      zr_set_global(G_SYM_PROCS, table)
    end
    found = zr_hash_lookup(table, sym)
    if found != QUNDEF
      return found
    end
    p = zr_native_proc(Machine.addr(:zr_symbol_block), sym)
    zr_hash_store(table, sym, p)
    p
  end

  G_SYM_PROCS = 61

  # Marks the task that runs eval's compiler (`on` true), or clears the
  # mark, and answers whether it was set. CRuby's compiler is C, which
  # walks its own Arrays and Hashes directly. zr's is Ruby, and its
  # Enumerable methods send `each`. While it runs, zr_enum_each takes the
  # core's own `each` for an instance of a core class, as SEND_CORE does,
  # so a program's Array#each does not run inside it. No code of the
  # program runs in the compiler; another thread that runs meanwhile has
  # a task of its own.
  #: (value) -> value
  def zr_eval_compiling_m(on)
    slot = Machine.static(:eval_task, 8)
    was = Machine.load64(slot, 0)
    if on == QTRUE
      Machine.store64(slot, 0, Machine.load64(zr_current_task_slot(), 0))
    else
      Machine.store64(slot, 0, 0)
    end
    zr_bool(was != 0)
  end

  # Calls `each` on `recv` and gives `blk` one value for each element: the
  # yielded value, or an Array of them when there are several (nil for
  # none), packed as rb_enum_values_pack packs them. Thus a core method
  # reads each element without a splat Array of its own. `args` go to
  # `each`, or nil. The adapter is a stack image of a Proc whose self is
  # `blk`. An `each` that keeps its block gets a cell (zr_block_proc).
  #: (value, value, value) -> value
  def zr_enum_each(recv, args, blk)
    d = Machine.slot(RProc.size)
    p = Machine.value(d)
    RBasic[p].flags = T_PROC | FL_ALLOCATED | FL_STACK
    RBasic[p].klass = zr_global(G_PROC)
    RProc[p].fn = Machine.addr(:zr_enum_each_block)
    RProc[p].meta = 0
    RProc[p].env = Machine.value(QNIL)
    RProc[p].self = blk
    RProc[p].cref = Machine.value(QNIL)
    RProc[p].blk = Machine.value(QNIL)
    RProc[p].home = 0
    RProc[p].serial = 0
    RProc[p].site = 0
    RProc[p].ret_home = 0
    RProc[p].ret_serial = 0
    RProc[p].spread = 0
    RProc[p].lambda = 0
    RProc[p].passed = 1
    if args == QNIL
      return zr_enum_send_each(recv, 0, 0, p)
    end
    zr_enum_send_each(recv, RArray[args].len, RArray[args].ptr, p)
  end

  # The `each` of an Enumerable method: sent by name, as rb_block_call
  # sends it, except inside eval's compiler, which takes the core's own
  # (zr_eval_compiling_m).
  #: (value, word, ptr, value) -> value
  def zr_enum_send_each(recv, argc, argv, p)
    mode = 0
    if Machine.load64(Machine.static(:eval_task, 8), 0) == Machine.load64(zr_current_task_slot(), 0)
      mode = SEND_CORE
    end
    zr_dispatch(0, recv, Machine.id(:each), argc, argv, mode, p)
  end

  # Calls `each` on `recv` and yields each step's values, as given, to the
  # program's block `user`, as enum.c's count_iter_i, flat_map_i and the
  # other rb_yield_values2 iterators do: a block of one parameter sees the
  # first of several. Then `inner` gets the step as one value and the
  # block's result. The adapter is on the stack, with `user` in its block
  # slot and `inner` as its self, so a step allocates nothing.
  #: (value, value, value, value) -> value
  def zr_enum_each_values(recv, args, user, inner)
    d = Machine.slot(RProc.size)
    p = Machine.value(d)
    RBasic[p].flags = T_PROC | FL_ALLOCATED | FL_STACK
    RBasic[p].klass = zr_global(G_PROC)
    RProc[p].fn = Machine.addr(:zr_enum_values_block)
    RProc[p].meta = 0
    RProc[p].env = Machine.value(QNIL)
    RProc[p].self = inner
    RProc[p].cref = Machine.value(QNIL)
    RProc[p].blk = user
    RProc[p].home = 0
    RProc[p].serial = 0
    RProc[p].site = 0
    RProc[p].ret_home = 0
    RProc[p].ret_serial = 0
    RProc[p].spread = 0
    RProc[p].lambda = 0
    RProc[p].passed = 1
    if args == QNIL
      return zr_enum_send_each(recv, 0, 0, p)
    end
    zr_enum_send_each(recv, RArray[args].len, RArray[args].ptr, p)
  end

  #: (value, word, ptr, value) -> value
  def zr_enum_values_block(p, argc, argv, blk)
    r = zr_yield(RProc[p].blk, argc, argv)
    return r if r == QUNDEF
    x = Machine.value(QNIL)
    if argc == 1
      x = Machine.value(Machine.load64(argv, 0))
    elsif argc > 1
      x = zr_ary_of(argc, argv)
    end
    zr_yield2(RProc[p].self, x, r)
  end

  #: (value, word, ptr, value) -> value
  def zr_enum_each_block(p, argc, argv, blk)
    if argc == 1
      return zr_yield1(RProc[p].self, Machine.value(Machine.load64(argv, 0)))
    end
    if argc == 0
      return zr_yield1(RProc[p].self, Machine.value(QNIL))
    end
    zr_yield1(RProc[p].self, zr_ary_of(argc, argv))
  end

  # Calls `each` on `recv`, yields each value directly to `blk`, and keeps
  # the results of `blk` in an Array. This is rb_block_call with
  # `collect_i`, which yields with rb_yield_values2 and so packs nothing.
  # Thus a block of one parameter sees the first value when `each` yielded
  # several, as `map` requires. A packing adapter cannot give that.
  #
  # This is here and not in `Enumerable#map` because a Ruby block that
  # takes `|*x|` to pass the values on allocates that Array for each
  # element: 2,000,000 elements take 242 ms that way and 65 ms here.
  # The self of the adapter is the pair [Array, block], so the collector
  # already finds both.
  #: (value, value, value) -> value
  def zr_enum_collect(recv, args, blk)
    kept = zr_ary_new(2)
    zr_ary_push(kept, zr_ary_new(4))
    zr_ary_push(kept, blk)
    p = zr_native_proc(Machine.addr(:zr_enum_collect_block), kept)
    # rb_lambda_call gives `each` the arity of the block, so a Hash yields
    # its key and value as two values to a block that takes two or more.
    zr_block_asks_pair(p, blk)
    if args == QNIL
      r = zr_enum_send_each(recv, 0, 0, p)
    else
      r = zr_enum_send_each(recv, RArray[args].len, RArray[args].ptr, p)
    end
    return r if r == QUNDEF
    zr_ary_at(kept, 0)
  end

  # Marks the adapter `p` as a block that takes a pair when `blk` takes two
  # or more values, as the `each` of a Hash requires of its block.
  # A Method as the block (`&method(:m)`) asks by the Method's required
  # count, as CRuby's method proc takes the yielded values.
  #: (value, value) -> void
  def zr_block_asks_pair(p, blk)
    need = zr_block_min_params(blk)
    if RProc[blk].meta == 0 && RProc[blk].fn == Machine.addr(:zr_method_block)
      a = zr_method_arity_of(RProc[blk].self)
      need = a >= 0 ? a : 0 - a - 1
    end
    if need > 1
      RProc[p].spread = 1
      RProc[p].lambda = 0
    end
  end

  # Returns how many values `blk` requires, or 0 for a block with no
  # parameters of its own (from a Symbol or a Method).
  #: (value) -> word
  def zr_block_min_params(blk)
    if RProc[blk].meta == 0
      return 0
    end
    zr_params_min(FrameMeta[RProc[blk].meta].params)
  end

  # Calls `each` on `recv` and calls the block for each element, as the
  # find_i of enum.c does through enum_yield: the element and the result of
  # the block go to `ask`. When `each` yields several values at a time, a
  # lambda of two or more parameters gets them spread, and any other block
  # gets one Array (rb_yield_force_blockarg). A Hash yields several values
  # at a time, as rb_block_call2 with RB_BLOCK_NO_USE_PACKED_ARGS makes it do.
  #: (value, value, value, value) -> value
  def zr_enum_each_asked(recv, args, blk, ask)
    kept = zr_ary_new(2)
    zr_ary_push(kept, blk)
    zr_ary_push(kept, ask)
    p = zr_native_proc(Machine.addr(:zr_enum_asked_block), kept)
    RProc[p].spread = 1
    RProc[p].lambda = 0
    if args == QNIL
      return zr_enum_send_each(recv, 0, 0, p)
    end
    zr_enum_send_each(recv, RArray[args].len, RArray[args].ptr, p)
  end

  #: (value, word, ptr, value) -> value
  def zr_enum_asked_block(p, argc, argv, blk)
    kept = RProc[p].self
    user = zr_ary_at(kept, 0)
    if argc == 0
      x = Machine.value(QNIL)
      r = zr_yield(user, 0, argv)
    elsif argc == 1
      x = Machine.value(Machine.load64(argv, 0))
      r = zr_yield1(user, x)
    else
      x = zr_ary_of(argc, argv)
      # rb_yield_force_blockarg spreads the values into a lambda of more
      # than one positional parameter, an optional one included.
      if RProc[user].lambda != 0 && RProc[user].meta != 0 && zr_params_positional(FrameMeta[RProc[user].meta].params) > 1
        r = zr_yield(user, argc, argv)
      else
        r = zr_yield1(user, x)
      end
    end
    return r if r == QUNDEF
    zr_yield2(zr_ary_at(kept, 1), x, r)
  end

  #: (value, word, ptr, value) -> value
  def zr_enum_collect_block(p, argc, argv, blk)
    kept = RProc[p].self
    v = zr_yield(zr_ary_at(kept, 1), argc, argv)
    return v if v == QUNDEF
    zr_ary_push(zr_ary_at(kept, 0), v)
    Machine.value(QNIL)
  end

  # The lazy stages that keep no state of their own. Each reads one
  # element, calls its block on it, and sends zero or one value on.
  LAZY_MAP = 0
  LAZY_SELECT = 1
  LAZY_REJECT = 2
  LAZY_FILTER_MAP = 3

  # One stage of a lazy enumerator. It calls `each` on `recv` and yields
  # each value directly to `blk`, so a block of one parameter sees the
  # first value when `each` yielded several, as ruby's lazy does. The
  # values that the stage keeps go to `out`, the block of the next stage.
  #
  # This is here and not in Ruby because a `|*values|` block allocates that
  # Array for each element and each stage. `map` then `select` over
  # 2,000,000 elements, three times, took 1.237 s that way, against ruby's
  # 0.670 s and YJIT's 0.631 s. Here it takes 0.542 s.
  #
  # `out` gets the values as the element was yielded, not packed, so the
  # result of the enumerator does not change: the next stage packs them
  # again if it must.
  #: (value, word, value, value) -> value
  def zr_lazy_stage(recv, kind, blk, out)
    kept = zr_ary_new(3)
    zr_ary_push(kept, zr_fix(kind))
    zr_ary_push(kept, blk)
    zr_ary_push(kept, out)
    p = zr_native_proc(Machine.addr(:zr_lazy_stage_block), kept)
    r = zr_enum_send_each(recv, 0, 0, p)
    return r if r == QUNDEF
    Machine.value(QNIL)
  end

  # This adapter is not in `zr_same_block` on purpose. A lazy block is kept
  # and called after the call that took it returns, so a `break` in it is
  # the LocalJumpError that ruby raises. If `zr_same_block` unwrapped the
  # adapter, the `break` would leave the walk instead.
  #: (value, word, ptr, value) -> value
  def zr_lazy_stage_block(p, argc, argv, blk)
    kept = RProc[p].self
    v = zr_yield(zr_ary_at(kept, 1), argc, argv)
    return v if v == QUNDEF
    kind = zr_fix2long(zr_ary_at(kept, 0))
    out = zr_ary_at(kept, 2)
    if kind == LAZY_MAP
      r = zr_yield1(out, v)
      return r if r == QUNDEF
      return Machine.value(QNIL)
    end
    if kind == LAZY_FILTER_MAP
      if v == QNIL || v == QFALSE
        return Machine.value(QNIL)
      end
      r = zr_yield1(out, v)
      return r if r == QUNDEF
      return Machine.value(QNIL)
    end
    kept_p = v != QNIL && v != QFALSE
    if kind == LAZY_REJECT
      kept_p = !kept_p
    end
    if kept_p
      r = zr_yield(out, argc, argv)
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  #: (value, value, value) -> value
  def zr_lazy_map(recv, blk, out)
    zr_lazy_stage(recv, LAZY_MAP, blk, out)
  end

  #: (value, value, value) -> value
  def zr_lazy_select(recv, blk, out)
    zr_lazy_stage(recv, LAZY_SELECT, blk, out)
  end

  #: (value, value, value) -> value
  def zr_lazy_reject(recv, blk, out)
    zr_lazy_stage(recv, LAZY_REJECT, blk, out)
  end

  #: (value, value, value) -> value
  def zr_lazy_filter_map(recv, blk, out)
    zr_lazy_stage(recv, LAZY_FILTER_MAP, blk, out)
  end

  # Returns a lambda whose body is the kernel function `fn`, with `self_`
  # as the object it works on: the Proc of a Symbol or a Method.
  #: (ptr, value) -> value
  def zr_native_proc(fn, self_)
    p = zr_alloc(T_PROC, zr_global(G_PROC), RProc.size)
    RProc[p].fn = fn
    RProc[p].meta = 0
    RProc[p].env = Machine.value(QNIL)
    RProc[p].self = self_
    RProc[p].cref = Machine.value(QNIL)
    RProc[p].blk = Machine.value(QNIL)
    RProc[p].home = 0
    RProc[p].serial = 0
    RProc[p].site = 0
    RProc[p].ret_home = 0
    RProc[p].ret_serial = 0
    RProc[p].spread = 0
    RProc[p].lambda = 1
    RProc[p].passed = 1
    p
  end

  # `-> { }`: the Proc of the literal, a lambda, with no call site that a
  # `break` can reach.
  #: (value) -> value
  def zr_proc_lambda(p)
    p = zr_block_proc(p)
    RProc[p].lambda = 1
    RProc[p].home = 0
    p
  end

  # `Proc#call`: calls the block with the arguments and a block of its own.
  #: (value, word, ptr, value, value) -> value
  def zr_proc_call(recv, argc, argv, cref, blk)
    Block.call(RProc[recv].fn, recv, argc, argv, blk)
  end

  # `b.call(args)` on a `&b` parameter bound to the block it was given. That
  # Proc can still be on the stack of its caller (Params#raw_block?). While
  # `call` is the program's own and the receiver is a plain Proc, the block
  # runs as Proc#call would run it. Otherwise the code makes the Proc and
  # sends `call` to it, as to any receiver. Nil gets the send, which raises
  # as usual.
  #: (value, word, word, ptr, word) -> value
  def zr_opt_block_call(recv, mid, argc, argv, mode)
    if recv != QNIL && (Machine.gates & GATE_PROC_CALL) == 0 && RBasic[recv].klass == zr_global(G_PROC)
      return Block.call(RProc[recv].fn, recv, argc, argv, Machine.value(QNIL))
    end
    zr_dispatch(0, zr_block_proc(recv), mid, argc, argv, mode, Machine.value(QNIL))
  end

  # Writes the origin of a block, as rb_block_to_s writes it after the
  # address: `(&:sym)` for the Proc of a Symbol, ` file:line` for a block
  # that a program wrote, and nothing for a core-made or Method Proc.
  # Returns false when the inspect of the Symbol raised; the exception is
  # then pending.
  #: (ptr, value) -> bool
  def zr_buf_block_where(b, blk)
    meta = RProc[blk].meta
    if RProc[blk].fn == Machine.addr(:zr_symbol_block)
      zr_buf_push(b, Machine.bytes("(&"), 2)
      s = zr_inspect(RProc[blk].self)
      if s == QUNDEF
        return false
      end
      zr_buf_str(b, s)
      zr_buf_byte(b, 41)
    elsif meta != 0 && FrameMeta[meta].file != 0
      zr_buf_byte(b, 32)
      zr_buf_push(b, FrameMeta[meta].file, FrameMeta[meta].file_len)
      zr_buf_byte(b, 58)
      zr_buf_long(b, FrameMeta[meta].line)
    end
    true
  end

  # Returns `#<Proc:0x... file:line (lambda)>`.
  #: (value, word, ptr, value, value) -> value
  def zr_proc_inspect(recv, argc, argv, cref, blk)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, recv)
    if !zr_buf_block_where(b, recv)
      zr_buf_free(b)
      return Machine.value(QUNDEF)
    end
    if RProc[recv].lambda != 0
      zr_buf_push(b, Machine.bytes(" (lambda)"), 9)
    end
    zr_buf_byte(b, 62)
    zr_buf_take_at(b, ENC_BINARY)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_proc_lambda_p(recv, argc, argv, cref, blk)
    zr_bool(RProc[recv].lambda != 0)
  end

  # `proc { }` and `Proc.new { }`: the Proc of the block, with no call site
  # that a `break` can reach after this.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_proc(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
    end
    p = zr_block_proc(blk)
    RProc[p].home = 0
    p
  end

  # `Proc.new { }`: as `proc`, and the arguments go to `initialize`, as
  # rb_proc_s_new passes them. For a subclass, it returns a copy of the
  # block as an instance of the subclass, as proc_new does.
  #: (value, word, ptr, value, value) -> value
  def zr_proc_s_new(recv, argc, argv, cref, blk)
    p = zr_kernel_proc(recv, 0, argv, cref, blk)
    return p if p == QUNDEF
    if RBasic[p].klass != recv
      p = zr_copy_cell(p)
      return p if p == QUNDEF
      RBasic[p].klass = recv
    end
    r = zr_send_blk(p, Machine.id(:initialize), argc, argv, blk)
    return r if r == QUNDEF
    p
  end

  # `lambda { }`: the Proc of the block, strict about its arguments, and
  # `return` leaves the lambda itself. A Proc passed with `&` must already
  # be a lambda (a `->`, a Method's, a Symbol's), and comes back unchanged.
  # It refuses all other Procs.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_lambda(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
    end
    if RProc[blk].passed != 0
      if RProc[blk].lambda != 0
        return blk
      end
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("the lambda method requires a literal block"), 42)
    end
    p = zr_block_proc(blk)
    RProc[p].lambda = 1
    p
  end

  # `&value` at a call: nil passes no block. A Proc passes itself, marked as
  # passed (it is not a literal block, which `lambda` refuses). A Symbol
  # passes its Proc. Any other value must respond to `to_proc`.
  #: (value) -> value
  def zr_block_pass(v)
    if v == QNIL || zr_symbol_p(v)
      if zr_symbol_p(v)
        return zr_sym_to_proc_here(v)
      end
      return v
    end
    if !zr_special_p(v) && zr_type(v) == T_PROC
      RProc[v].passed = 1
      return v
    end
    if zr_find_method(zr_class_of(v), Machine.id(:to_proc)) == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      zr_buf_class_of(b, v)
      zr_buf_push(b, Machine.bytes(" into Proc"), 10)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    pr = zr_send(v, Machine.id(:to_proc), 0, 0)
    if pr == QUNDEF || (!zr_special_p(pr) && zr_type(pr) == T_PROC)
      return pr
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("can't convert "), 14)
    zr_buf_class_of(b, v)
    zr_buf_push(b, Machine.bytes(" to Proc ("), 10)
    zr_buf_class_of(b, v)
    zr_buf_push(b, Machine.bytes("#to_proc gives "), 15)
    zr_buf_class_of(b, pr)
    zr_buf_push(b, Machine.bytes(")"), 1)
    zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end

  # Calls the block with `argc` arguments. Each yield is a back edge of the
  # loop that makes it, so this one place yields to the scheduler for every
  # kernel iterator. Thus a thread that walks a large table yields to the
  # scheduler as a compiled loop does, and a kill reaches it.
  #: (value, word, ptr) -> value
  def zr_yield(blk, argc, argv)
    if blk == QNIL
      # No block takes the keywords the caller flagged.
      zr_kw_take()
      return zr_local_jump_error(Machine.bytes("no block given (yield)"), 22, Machine.id(:noreason), Machine.value(QNIL))
    end
    # The caller flagged its keywords in the task. A switch at the poll
    # runs other code, whose calls take the flag, so it is kept aside.
    kw = zr_kw_take()
    tick = zr_preempt()
    return tick if tick == QUNDEF
    Task[zr_task()].kw = kw
    Block.call(RProc[blk].fn, blk, argc, argv, Machine.value(QNIL))
  end

  #: (value, value) -> value
  def zr_yield1(blk, v)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(v))
    zr_yield(blk, 1, slot)
  end

  #: (value, value, value) -> value
  def zr_yield2(blk, a, b)
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(a))
    Machine.store64(slot, 8, Machine.word(b))
    zr_yield(blk, 2, slot)
  end

  # Returns the arguments that a block binds. A single Array, or a value
  # whose `to_ary` returns one, spreads over the parameters when the shape
  # of the block requires it (`spread`). Missing arguments are nil, and
  # extra ones are dropped. The code keeps the spread Array in the slot at
  # `keep` of the block's frame record, so a new result of `to_ary` stays
  # rooted while the parameters bind. A block with optional parameters
  # gets a copy (`spread` is 2), as CRuby copies the arguments before a
  # default runs. Thus a default that changes the Array changes nothing the
  # block was called with. Returns the argument count (a fixnum) to read
  # from `argv_out`, or QUNDEF when `to_ary` raised.
  #: (word, ptr, word, ptr, ptr) -> value
  def zr_block_args(argc, argv, spread, argv_out, keep)
    if spread != 0 && argc == 1
      v = Machine.value(Machine.load64(argv, 0))
      if !zr_special_p(v) && zr_type(v) == T_ARRAY
        return zr_block_spread(v, spread, argv_out, keep)
      end
      responds = zr_special_p(v) ? Machine.value(QFALSE) : zr_check_funcall(v, Machine.id(:to_ary))
      return responds if responds == QUNDEF
      if responds == QTRUE
        a = zr_send(v, Machine.id(:to_ary), 0, 0)
        return a if a == QUNDEF
        if !zr_special_p(a) && zr_type(a) == T_ARRAY
          return zr_block_spread(a, spread, argv_out, keep)
        end
        if a != QNIL
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_push(b, Machine.bytes("can't convert "), 14)
          zr_buf_class_of(b, v)
          zr_buf_push(b, Machine.bytes(" to Array ("), 11)
          zr_buf_class_of(b, v)
          zr_buf_push(b, Machine.bytes("#to_ary gives "), 14)
          zr_buf_class_of(b, a)
          zr_buf_push(b, Machine.bytes(")"), 1)
          return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
        end
      end
    end
    Machine.store64(argv_out, 0, argv)
    zr_fix(argc)
  end

  # Returns the Array `a` as the arguments of a block: rooted at `keep`,
  # and copied first when the defaults of the block could change it.
  #: (value, word, ptr, ptr) -> value
  def zr_block_spread(a, spread, argv_out, keep)
    Machine.store64(keep, 0, Machine.word(a))
    if spread == 2
      a = zr_ary_of(RArray[a].len, RArray[a].ptr)
      Machine.store64(keep, 0, Machine.word(a))
    end
    Machine.store64(argv_out, 0, RArray[a].ptr)
    zr_fix(RArray[a].len)
  end

  # Reads the arguments again after Ruby code ran between two bindings.
  # The `to_ary` of a destructured parameter can grow or empty the spread
  # Array, so the code reads its buffer and length again.
  #: (value, ptr) -> ptr
  def zr_block_argv(kept, argv)
    if kept == QNIL
      return argv
    end
    RArray[kept].ptr
  end

  #: (value, word) -> word
  def zr_block_argc(kept, argc)
    if kept == QNIL || RArray[kept].len >= argc
      return argc
    end
    RArray[kept].len
  end

  # Returns the serial that makes the frame at `rec` different from all
  # other frames at that address. A frame gets its serial the first time
  # code asks for it, because most frames are never a home. A frame with
  # no serial has 0, which no home has.
  #: (ptr) -> word
  def zr_frame_serial(rec)
    if rec == 0
      return 0
    end
    s = Frame[rec].serial
    if s == 0
      t = zr_task()
      s = Task[t].serial + 1
      Task[t].serial = s
      Frame[rec].serial = s
    end
    s
  end

  # Returns the name that called the method frame `rec`, or 0 for a frame
  # that is not a method or whose name is the name in its meta.
  #: (ptr) -> word
  def zr_frame_mid(rec)
    e = Frame[rec].entry
    e == 0 ? 0 : MEntry[e].mid
  end

  # Whether the frame `home` with `serial` is still on the stack.
  #: (ptr, word) -> bool
  def zr_frame_live(home, serial)
    rec = Task[zr_task()].top
    while rec != 0
      if rec == home
        return Frame[rec].serial == serial
      end
      rec = Frame[rec].prev
    end
    false
  end

  #: (word, value, ptr, word) -> value
  def zr_signal(kind, value, home, site)
    t = zr_task()
    Task[t].pending_kind = kind
    Task[t].pending = value
    Task[t].pending_home = home
    Task[t].pending_site = site
    Machine.value(QUNDEF)
  end

  # Returns a LocalJumpError with its reason (`:break`, `:return`,
  # `:noreason`) and the value of the jump.
  #: (ptr, word, word, value) -> value
  def zr_local_jump_error(bytes, len, reason, v)
    exc = zr_exc_new(zr_global(G_LOCAL_JUMP_ERROR), zr_str_new(bytes, len))
    zr_ivar_set(exc, Machine.id(:@exit_value), v)
    zr_ivar_set(exc, Machine.id(:@reason), zr_sym(reason))
    zr_raise(exc)
  end

  # `break v` in the block `p`.
  #: (value, value) -> value
  def zr_break(p, v)
    unless (RBasic[p].flags & FL_ISOLATED) == 0 && zr_frame_live(RProc[p].home, RProc[p].serial) && zr_block_call_live(p)
      return zr_local_jump_error(Machine.bytes("break from proc-closure"), 23, Machine.id(:break), v)
    end
    zr_signal(PENDING_BREAK, v, RProc[p].home, RProc[p].site)
  end

  # Whether the call that got `p` is still running. A break leaves that
  # call, so after it returns there is nothing to break out of, although
  # the method that contains the block can still run: the block was kept
  # and called later.
  #
  # The call that the frame `home` runs now is the frame whose `prev` is
  # `home`, because a frame makes one call at a time. That call got the
  # block when its block is this block: this Proc, or one made from the
  # same literal in the same run of `home`, as `instance_exec` makes to run
  # the block under a different self.
  #: (value) -> bool
  def zr_block_call_live(p)
    home = RProc[p].home
    rec = Task[zr_task()].top
    while rec != 0 && rec != home
      if Frame[rec].prev == home
        # A `define_method` method gets its block from the call, not from where
        # its body was written. Its frame keeps that block in `defined`.
        if zr_bmethod_entry(rec) != 0 && zr_same_block(Frame[rec].defined, p)
          return true
        end
        # The call at the literal's site got the literal's descriptor. A call
        # that got a Proc in its own cell got it with `&`, after the call at
        # the site returned (`capture { break }` then `yielding(&b)`), and
        # ruby raises there as for any orphan break.
        given = Frame[rec].blk
        if !zr_special_p(given) && zr_type(given) == T_PROC && (RBasic[given].flags & FL_STACK) == 0
          return false
        end
        return zr_same_block(given, p)
      end
      rec = Frame[rec].prev
    end
    false
  end

  # The each adapters of the kernel (zr_enum_each, zr_enum_collect) are in
  # place of the block that they give values to, so a `break` in that block
  # leaves the `each` that got the adapter. One adapter keeps its block as
  # its self, and the other keeps it second in a pair.
  #: (value, value) -> bool
  def zr_same_block(given, p)
    if given == p
      return true
    end
    if zr_special_p(given) || zr_type(given) != T_PROC
      return false
    end
    if RProc[given].fn == Machine.addr(:zr_enum_each_block)
      return zr_same_block(RProc[given].self, p)
    end
    if RProc[given].fn == Machine.addr(:zr_enum_collect_block)
      return zr_same_block(zr_ary_at(RProc[given].self, 1), p)
    end
    RProc[given].fn == RProc[p].fn && RProc[given].home == RProc[p].home && RProc[given].serial == RProc[p].serial && RProc[given].site == RProc[p].site
  end

  # `return v` in the block `p`: leaves the method that contains the block.
  #: (value, value) -> value
  def zr_return(p, v)
    # A shareable Proc has no link to the method that contains it, so there
    # is no method for its `return` to leave.
    unless (RBasic[p].flags & FL_ISOLATED) == 0 && zr_frame_live(RProc[p].ret_home, RProc[p].ret_serial)
      return zr_local_jump_error(Machine.bytes("unexpected return"), 17, Machine.id(:return), v)
    end
    # A block in a `class << self` body leaves the method around the body,
    # as a `return` in the body itself does. The body catches no return.
    home = RProc[p].ret_home
    if FrameMeta[Frame[home].meta].kind == KIND_SCLASS
      return zr_return_out(home, v)
    end
    zr_signal(PENDING_RETURN, v, home, 0)
  end

  # At a call site with a block: returns the value of the pending break
  # when it is for this site, else undef (the pending unwind stays).
  #: (ptr, word) -> value
  def zr_catch_break(rec, site)
    t = zr_task()
    if Task[t].pending_kind == PENDING_BREAK && Task[t].pending_home == rec && Task[t].pending_site == site
      v = Task[t].pending
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending = Machine.value(QNIL)
      return v
    end
    Machine.value(QUNDEF)
  end

  # A `return` in an eval or in a `class << self` body has no home. The
  # pending unwind belongs to the method that holds the scope, which set up
  # the catch. The scopes outside the method are in the frame metadata:
  # when they end at the toplevel or a class body, or the method no longer
  # runs, the return raises LocalJumpError, as ruby's does. An eval whose
  # scope is not known leaves the unwind to the nearest method.
  #: (value) -> value
  def zr_return_here(v)
    zr_return_out(Task[zr_task()].top, v)
  end

  # The same, for a `return` in the scope of the frame `rec`.
  #: (ptr, value) -> value
  def zr_return_out(rec, v)
    zr_return_scope(Frame[rec].prev, FrameMeta[Frame[rec].meta].parent, v)
  end

  # A `return` in the scope `meta`, whose frame runs at or below `rec`.
  #: (ptr, ptr, value) -> value
  def zr_return_scope(rec, meta, v)
    in_block = false
    while meta != 0 && FrameMeta[meta].kind != KIND_DEF
      kind = FrameMeta[meta].kind
      # An eval straight in the toplevel returns from the file.
      if (kind == KIND_MAIN || kind == KIND_TOP) && !in_block
        return zr_signal(PENDING_RETURN, v, 0, 0)
      end
      if kind != KIND_BLOCK && kind != KIND_SCLASS && kind != KIND_EVAL
        return zr_local_jump_error(Machine.bytes("unexpected return"), 17, Machine.id(:return), v)
      end
      in_block = in_block || kind != KIND_EVAL
      meta = FrameMeta[meta].parent
    end
    if meta != 0 && !zr_meta_running(rec, meta)
      return zr_local_jump_error(Machine.bytes("unexpected return"), 17, Machine.id(:return), v)
    end
    zr_signal(PENDING_RETURN, v, 0, 0)
  end

  # Whether a frame from `rec` down runs the function of `meta`.
  #: (ptr, ptr) -> bool
  def zr_meta_running(rec, meta)
    while rec != 0
      if Frame[rec].meta == meta
        return true
      end
      rec = Frame[rec].prev
    end
    false
  end

  # In the landing block of a method that contains an eval: returns the
  # value of the pending return when it has no home of its own, else undef.
  #: () -> value
  def zr_catch_return_here
    t = zr_task()
    if Task[t].pending_kind == PENDING_RETURN && Task[t].pending_home == 0
      v = Task[t].pending
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending = Machine.value(QNIL)
      return v
    end
    Machine.value(QUNDEF)
  end

  # In the landing block of a method: returns the value of the pending
  # return when it is for this method, else undef.
  #: (ptr) -> value
  def zr_catch_return(rec)
    t = zr_task()
    if Task[t].pending_kind == PENDING_RETURN && Task[t].pending_home == rec
      v = Task[t].pending
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending = Machine.value(QNIL)
      return v
    end
    Machine.value(QUNDEF)
  end

  # `block_given?` reads the block of the frame that called it.
  #: (value, word, ptr, value, value) -> value
  def zr_block_given_p(recv, argc, argv, cref, blk)
    caller = Frame[Task[zr_task()].top].prev
    zr_bool(Frame[caller].blk != QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_int_times(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route_blk(recv, Machine.id(:times), argc, argv, blk)
    end
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:times), argc, argv, recv)
    end
    if (Machine.gates & (GATE_LT | GATE_SUCC)) != 0
      return zr_int_times_sent(recv, blk)
    end
    n = zr_fix2long(recv)
    i = 0
    while i < n
      r = zr_yield1(blk, zr_fix(i))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # Whether Integer#< is ruby's own, which num_step_negative_p asks
  # (method_basic_p) before it reads a step's sign natively.
  #: () -> value
  def zr_int_lt_basic_p
    zr_bool((Machine.gates & GATE_LT) == 0)
  end

  # Integer#times as <internal:numeric> writes it, for a program that
  # redefined Integer#< or Integer#succ: `while i < self`, then
  # `i = i.succ`, each a send.
  #: (value, value) -> value
  def zr_int_times_sent(recv, blk)
    slot = Machine.slot(8)
    i = zr_fix(0)
    while true
      Machine.store64(slot, 0, Machine.word(recv))
      more = zr_send(i, Machine.id(:<), 1, slot)
      return more if more == QUNDEF
      if more == QNIL || more == QFALSE
        return recv
      end
      r = zr_yield1(blk, i)
      return r if r == QUNDEF
      i = zr_send(i, Machine.id(:succ), 0, slot)
      return i if i == QUNDEF
    end
    recv
  end

  # Writes the bound of `upto` (dir 1) or `downto` (dir -1) to `out`. A
  # fixnum stays as it is, and a Float becomes its floor or ceiling. Any
  # other value coerces or fails, as an Integer operand does.
  #: (value, ptr, ptr, word) -> value
  def zr_int_bound(recv, argv, out, dir)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_float_p(other)
      d = zr_float_value(other)
      if zr_nan_p(d)
        # Nothing compares with NaN, so the loop is empty.
        Machine.store64(out, 0, zr_fix2long(recv) - dir)
        return Machine.value(QNIL)
      end
      d = dir > 0 ? Machine.floor(d) : Machine.ceil(d)
      if d > Machine.f64(4890909195324358656)
        d = Machine.f64(4890909195324358656)
      elsif d < Machine.f64(0) - Machine.f64(4890909195324358656)
        d = Machine.f64(0) - Machine.f64(4890909195324358656)
      end
      Machine.store64(out, 0, Machine.to_int(d))
      return Machine.value(QNIL)
    end
    if zr_big_p(other)
      # A Bignum bound is past every fixnum: the loop runs to the end of the
      # fixnum range, or not at all.
      beyond = zr_send(other, Machine.id(:negative?), 0, 0)
      return beyond if beyond == QUNDEF
      toward = beyond == QTRUE ? 0 - 1 : 1
      if toward == dir
        Machine.store64(out, 0, dir > 0 ? 4611686018427387903 : 0 - 4611686018427387904)
      else
        Machine.store64(out, 0, zr_fix2long(recv) - dir)
      end
      return Machine.value(QNIL)
    end
    if !zr_fixnum_p(other)
      return zr_cmperr(recv, other)
    end
    zr_int_operand(recv, argv, out, 0, 3)
  end

  # Returns the size of `upto` or `downto`: the number of steps to the
  # bound, exact for a Bignum, and 0 on the wrong side. Returns nil for a
  # bound that is not a number.
  #: (value, word, ptr, word) -> value
  def zr_int_step_size(recv, argc, argv, dir)
    if argc != 1
      return Machine.value(QNIL)
    end
    other = Machine.value(Machine.load64(argv, 0))
    if zr_big_p(other)
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(dir > 0 ? recv : other))
      span = zr_send(dir > 0 ? other : recv, Machine.id(:-), 1, slot)
      return span if span == QUNDEF
      if zr_send(span, Machine.id(:negative?), 0, 0) == QTRUE
        return zr_fix(0)
      end
      Machine.store64(slot, 0, Machine.word(zr_fix(1)))
      return zr_send(span, Machine.id(:+), 1, slot)
    end
    if !zr_fixnum_p(other) && !zr_float_p(other)
      return Machine.value(QNIL)
    end
    out = Machine.slot(8)
    r = zr_int_bound(recv, argv, out, dir)
    return r if r == QUNDEF
    n = ((Machine.load64(out, 0) - zr_fix2long(recv)) * dir) + 1
    zr_fix(n < 0 ? 0 : n)
  end

  # Whether an upto or downto stop is no Integer and no Float.
  #: (value) -> bool
  def zr_int_unsized_stop_p(other)
    !zr_fixnum_p(other) && !zr_float_p(other) && !zr_big_p(other)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_int_upto(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route_blk(recv, Machine.id(:upto), argc, argv, blk)
    end
    if blk == QNIL
      # A stop that is not a number gets a size that compares the two
      # ends when it is asked for, as ruby_num_interval_step_size does.
      if argc == 1 && zr_int_unsized_stop_p(Machine.value(Machine.load64(argv, 0)))
        slot = Machine.slot(16)
        Machine.store64(slot, 0, Machine.word(zr_sym(Machine.id(:upto))))
        Machine.store64(slot, 8, Machine.load64(argv, 0))
        return zr_send(recv, Machine.id(:interval_enum), 2, slot)
      end
      return zr_enum_for(recv, Machine.id(:upto), argc, argv, zr_int_step_size(recv, argc, argv, 1))
    end
    out = Machine.slot(8)
    r = zr_int_bound(recv, argv, out, 1)
    return r if r == QUNDEF
    i = zr_fix2long(recv)
    last = Machine.load64(out, 0)
    while i <= last
      r = zr_yield1(blk, zr_fix(i))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_int_downto(recv, argc, argv, cref, blk)
    if !zr_fixnum_p(recv)
      return zr_big_route_blk(recv, Machine.id(:downto), argc, argv, blk)
    end
    if blk == QNIL
      # A stop that is not a number gets a size that compares the two
      # ends when it is asked for, as ruby_num_interval_step_size does.
      if argc == 1 && zr_int_unsized_stop_p(Machine.value(Machine.load64(argv, 0)))
        slot = Machine.slot(16)
        Machine.store64(slot, 0, Machine.word(zr_sym(Machine.id(:downto))))
        Machine.store64(slot, 8, Machine.load64(argv, 0))
        return zr_send(recv, Machine.id(:interval_enum), 2, slot)
      end
      return zr_enum_for(recv, Machine.id(:downto), argc, argv, zr_int_step_size(recv, argc, argv, 0 - 1))
    end
    out = Machine.slot(8)
    r = zr_int_bound(recv, argv, out, 0 - 1)
    return r if r == QUNDEF
    i = zr_fix2long(recv)
    last = Machine.load64(out, 0)
    while i >= last
      r = zr_yield1(blk, zr_fix(i))
      return r if r == QUNDEF
      i -= 1
    end
    recv
  end

  # A builtin iterator called with no block: returns
  # `to_enum(:name, *args)`, with the count of values that it would yield,
  # or nil when that count is unknown.
  #: (value, word, word, ptr, value) -> value
  def zr_enum_for(recv, mid, argc, argv, size)
    # A builtin called through an alias (`filter` for `select`, `each_pair`
    # for `each`) returns an enumerator with the name of the alias, as ruby's
    # records the called name.
    top = Task[zr_task()].top
    if Frame[top].entry != 0 && Frame[top].meta != 0 && FrameMeta[Frame[top].meta].kind == KIND_BUILTIN
      mid = zr_frame_mid(top)
    end
    args = zr_ary_new(argc + 2)
    zr_ary_push(args, zr_sym(mid))
    i = 0
    while i < argc
      zr_ary_push(args, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    zr_ary_push(args, size)
    zr_send(recv, Machine.id(:enum_with_size), RArray[args].len, RArray[args].ptr)
  end

  # The loop reads the length of the Array again at each step, because the
  # block can change it.
  #: (value, word, ptr, value, value) -> value
  def zr_ary_each(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:each), argc, argv, zr_fix(RArray[recv].len))
    end
    i = 0
    while i < RArray[recv].len
      r = zr_yield1(blk, zr_ary_at(recv, i))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # Sets up the two frames of an iterator that a site runs inline (the
  # lowering's Function::Iterators). The first is the builtin's frame, as
  # zr_builtin_fn makes it. The second is the block's frame, as the block's
  # own prologue would make it. Both are in `recs` on the caller's stack,
  # linked under the caller's frame, which is the top. The site stores the
  # caller's frame back when the loop ends, and its landing block does the
  # same on a pending unwind. The gate that the site checked tells that
  # `mid` is the builtin that the receiver's class finds. With no
  # refinement in use, the method cache gives the entry; a refined lookup
  # would find the refinement, so the walk does.
  #: (ptr, value, word, ptr) -> void
  def zr_iter_enter(recs, recv, mid, meta)
    t = zr_task()
    home = Task[t].top
    klass = zr_class_of(recv)
    e = Task[t].refine == QNIL ? zr_find_method(klass, mid) : zr_search_method(klass, mid)
    Frame[recs].prev = home
    Frame[recs].meta = MEntry[e].meta
    Frame[recs].line = 0
    Frame[recs].serial = 0
    Frame[recs].self = recv
    Frame[recs].cref = Machine.value(QNIL)
    Frame[recs].blk = Machine.value(QNIL)
    Frame[recs].nvalues = 0
    Frame[recs].entry = e
    Frame[recs].svars = Machine.value(QNIL)
    Frame[recs].defined = Machine.value(QNIL)
    b = recs + Frame.size
    Frame[b].prev = recs
    Frame[b].meta = meta
    Frame[b].line = 0
    Frame[b].serial = 0
    Frame[b].self = Frame[home].self
    Frame[b].cref = Frame[home].cref
    Frame[b].blk = Frame[home].blk
    Frame[b].nvalues = 0
    Frame[b].entry = 0
    Frame[b].svars = Machine.value(QNIL)
    Frame[b].defined = Machine.value(QNIL)
    Task[t].top = b
  end

  # Whether `v` is an Array whose `each` is Array's own. Then an Enumerable
  # method can walk it by index and give the same result as `each`.
  #: (value) -> value
  def zr_ary_plain_each_p(v)
    if zr_special_p(v) || zr_type(v) != T_ARRAY
      return Machine.value(QFALSE)
    end
    zr_key_builtin_p(v, Machine.id(:each), Machine.addr(:zr_ary_each)) ? Machine.value(QTRUE) : Machine.value(QFALSE)
  end

  #: (value, value) -> value
  def zr_ary_each_with_index_m(recv, blk)
    zr_ary_each_with_index(recv, 0, 0, Machine.value(QNIL), blk)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_ary_each_with_index(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:each_with_index), argc, argv, zr_fix(RArray[recv].len))
    end
    i = 0
    while i < RArray[recv].len
      r = zr_yield2(blk, zr_ary_at(recv, i), zr_fix(i))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_ary_each_index(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:each_index), argc, argv, zr_fix(RArray[recv].len))
    end
    i = 0
    while i < RArray[recv].len
      r = zr_yield1(blk, zr_fix(i))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # `map`: puts the results into a new Array, which the frame keeps rooted
  # through the receiver's slot.
  #: (value, word, ptr, value, value) -> value
  def zr_ary_map(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:map), argc, argv, zr_fix(RArray[recv].len))
    end
    out = zr_ary_new(RArray[recv].len)
    i = 0
    while i < RArray[recv].len
      r = zr_yield1(blk, zr_ary_at(recv, i))
      return r if r == QUNDEF
      zr_ary_push(out, r)
      i += 1
    end
    out
  end

  # `collect`: the body of map, and an Enumerator with the name `collect`,
  # as CRuby gives the name that it was called by.
  #: (value, word, ptr, value, value) -> value
  def zr_ary_collect(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:collect), argc, argv, zr_fix(RArray[recv].len))
    end
    zr_ary_map(recv, argc, argv, cref, blk)
  end

  # `select`/`reject`: `keep` tells which block results keep the element.
  #: (value, value, bool) -> value
  def zr_ary_filter(recv, blk, keep)
    out = zr_ary_new(4)
    i = 0
    while i < RArray[recv].len
      v = zr_ary_at(recv, i)
      r = zr_yield1(blk, v)
      return r if r == QUNDEF
      if (r != QNIL && r != QFALSE) == keep
        zr_ary_push(out, zr_ary_at(recv, i))
      end
      i += 1
    end
    out
  end

  #: (value, word, ptr, value, value) -> value
  def zr_ary_select(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:select), argc, argv, zr_fix(RArray[recv].len))
    end
    zr_ary_filter(recv, blk, true)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_ary_reject(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_enum_for(recv, Machine.id(:reject), argc, argv, zr_fix(RArray[recv].len))
    end
    zr_ary_filter(recv, blk, false)
  end

  # Returns the element that a block passed on to `each` sees: the one
  # yielded value, or the several values as an Array.
  #: (value) -> value
  def zr_enum_value(values)
    if RArray[values].len == 1
      return zr_ary_at(values, 0)
    end
    if RArray[values].len == 0
      return Machine.value(QNIL)
    end
    values
  end

  # A proc that a core method makes, as `curry` and `>>` do. Its
  # parameters are `[[:rest]]` and its arity is -1, whatever the block
  # behind it takes, as for the procs that CRuby makes in C.
  #: () -> ptr
  def zr_anonymous_meta
    meta = Machine.static(:anonymous_meta, FrameMeta.size)
    if FrameMeta[meta].params == 0
      table = zr_xmalloc(24)
      Machine.store64(table, 0, 1)
      Machine.store64(table, 8, PARAM_REST)
      Machine.store64(table, 16, 0)
      FrameMeta[meta].params = table
      FrameMeta[meta].arity = 0 - 1
      FrameMeta[meta].kind = KIND_BLOCK
      FrameMeta[meta].owner = Machine.value(QNIL)
    end
    meta
  end

  #: (value) -> value
  def zr_proc_anonymous(p)
    RProc[p].meta = zr_anonymous_meta()
    p
  end

  # Two Procs are equal when they wrap one block over one scope, as `dup`
  # and `clone` make them.
  #: (value, word, ptr, value, value) -> value
  def zr_proc_eq(recv, argc, argv, cref, blk)
    other = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(other) || zr_type(other) != T_PROC
      return Machine.value(QFALSE)
    end
    zr_bool(RProc[recv].fn == RProc[other].fn && RProc[recv].env == RProc[other].env &&
            RProc[recv].self == RProc[other].self && RProc[recv].lambda == RProc[other].lambda)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_proc_hash(recv, argc, argv, cref, blk)
    zr_fix(zr_hash_mix(Machine.word(RProc[recv].fn) ^ Machine.word(RProc[recv].env)) & 4611686018427387903)
  end
end
