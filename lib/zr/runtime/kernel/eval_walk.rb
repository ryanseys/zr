# The frames of code that the eval walker runs (lib/zr/eval/interpreter/tree.rb).
#
# The walker's own frames show in no backtrace, as ruby's compiler and VM
# are C (Lower::Function#walker_frame?). A call from walked code runs
# under a frame that this file pushes: its FrameMeta names the walked
# scope (an eval's code, a method or a block that the string defines),
# and its line is the line of the call.
# So a backtrace, caller_locations, a warning's place and `binding` in
# the callee see the walked code, as they see compiled code.

module Zr::Kern
  # A FrameMeta for one scope of walked code, never freed: the walker
  # keeps one for each scope, so their number is that of the scopes.
  # `kind` is a KIND_ number, `name` a Symbol or nil, `owner` the class of
  # a method or nil, `file` the path that the frame shows, and `parent` the
  # meta of the scope around it (a block's, or an eval's caller), as an
  # Integer, or nil. `evaled` is true for code with no absolute path, and
  # `box` the Ruby::Box of the walked code, or nil for main.
  #: (value, value, value, value, value, value, value) -> value
  def zr_walk_meta_m(kind, name, owner, file, parent, evaled, box)
    m = zr_xmalloc(FrameMeta.size)
    Libc.memset(m, Machine.i32(0), FrameMeta.size)
    FrameMeta[m].kind = zr_fix2long(kind)
    if name != QNIL
      FrameMeta[m].name = zr_sym2id(name)
    end
    FrameMeta[m].owner = owner
    len = RString[file].len
    path = zr_xmalloc(len + 1)
    zr_memcpy(path, RString[file].ptr, len)
    Machine.store8(path + len, 0, Machine.i8(0))
    FrameMeta[m].file = path
    FrameMeta[m].file_len = len
    if parent != QNIL
      FrameMeta[m].parent = Machine.ptr(zr_fix2long(parent))
    end
    if evaled == QTRUE
      FrameMeta[m].evaled = 1
    end
    if box != QNIL
      FrameMeta[m].box = box
    end
    zr_fix(Machine.word(m))
  end

  # The meta of a rescue clause in walked code: a copy of `meta` whose
  # rescues table (zr_frame_levels) has the clause's `begin` line first,
  # then the lines of the clauses around it. CRuby runs a rescue clause in
  # a frame of its own, so a caller list from the clause counts a level
  # more, which shows the scope at the `begin`.
  #: (value, value) -> value
  def zr_walk_rescue_meta_m(meta, line)
    from = Machine.ptr(zr_fix2long(meta))
    m = zr_xmalloc(FrameMeta.size)
    zr_memcpy(m, from, FrameMeta.size)
    old = FrameMeta[from].rescues
    n = old == 0 ? 0 : Machine.load64(old, 0)
    table = zr_xmalloc(16 + (n * 8))
    Machine.store64(table, 0, n + 1)
    # The node id of a frame that zr_walk_send_m pushes for this meta.
    node = FrameMeta[from].evaled != 0 ? 1 : 0
    Machine.store64(table, 8, (node << 32) | (zr_fix2long(line) & WALK_LINE_MASK))
    if n > 0
      zr_memcpy(table + 16, old + 8, n * 8)
    end
    FrameMeta[m].rescues = table
    zr_fix(Machine.word(m))
  end

  # The meta of the frame that called eval, as an Integer, or nil: an
  # eval's code shows that frame's label (KIND_EVAL).
  # The walker's own frames show in no backtrace (`frameless`), so they
  # are passed.
  #: () -> value
  def zr_walk_caller_meta_m
    rec = zr_eval_frame()
    while rec != 0 && FrameMeta[Frame[rec].meta].frameless != 0
      rec = zr_frame_with_file(Frame[rec].prev)
    end
    if rec == 0
      return Machine.value(QNIL)
    end
    zr_fix(Machine.word(Frame[rec].meta))
  end

  # Sends `name` with the Array `args` to `recv` from walked code, under
  # a frame of `at` (`[meta, line, self]`, or nil for no frame). `mode` is
  # zr_dispatch's (0 for no receiver or self, 2 for another receiver),
  # plus WALK_KEYWORDS when the last element of `args` is a keyword Hash,
  # and WALK_NEW for a `new` that compiles to opt_new (zr_new_cached).
  WALK_KEYWORDS = 256
  WALK_NEW = 512
  # The bits of Frame.line that hold the line (the node id is above them).
  WALK_LINE_MASK = 4294967295
  # The node id of a frame in a walked eval: the walker keeps no spots,
  # so a Location there is one in an eval whose lines were not kept
  # (zr_frame_place_id), as a compiled eval's is.
  WALK_EVAL_NODE = 4294967296

  #: (value, value, value, value, value, value) -> value
  def zr_walk_send_m(at, recv, name, args, blk, mode)
    m = zr_fix2long(mode)
    if (m & WALK_KEYWORDS) != 0
      zr_kw_pass()
      m = m - WALK_KEYWORDS
    end
    fresh = (m & WALK_NEW) != 0
    if fresh
      m = m - WALK_NEW
    end
    if at == QNIL
      return fresh ? zr_walk_new(recv, args, blk, m) : zr_dispatch(0, recv, zr_sym2id(name), RArray[args].len, RArray[args].ptr, m, blk)
    end
    rec = Machine.slot(Frame.size)
    zr_walk_push(rec, at)
    r = fresh ? zr_walk_new(recv, args, blk, m) : zr_dispatch(0, recv, zr_sym2id(name), RArray[args].len, RArray[args].ptr, m, blk)
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  # `recv.new(*args)` as opt_new runs it: the object and its initialize,
  # with no frame and no event of Class#new, through a call cache that
  # starts empty (the walker keeps none for a site): 2 * CALL_WAYS entries,
  # those of `new` and of `initialize`.
  #: (value, value, value, word) -> value
  def zr_walk_new(recv, args, blk, mode)
    cc = Machine.slot(CallCache.size * 8)
    Libc.memset(cc, Machine.i32(0), CallCache.size * 8)
    zr_new_cached(cc, recv, RArray[args].len, RArray[args].ptr, blk, mode)
  end

  # A `class`, a `module` and a constant write of walked code, under a
  # frame of `at` (or none, for nil), as zr_walk_send_m sends: the
  # constant records the walked file and line, as compiled code's does
  # (zr_const_set_at), where it would record a frame of the walker.
  #: (value, value, value, value, value, value) -> value
  def zr_walk_class_define_m(at, scope, name, sup, given, scoped)
    if at == QNIL
      return zr_class_define_m(scope, name, sup, given, scoped)
    end
    rec = Machine.slot(Frame.size)
    zr_walk_push(rec, at)
    r = zr_class_define_m(scope, name, sup, given, scoped)
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  #: (value, value, value, value) -> value
  def zr_walk_module_define_m(at, scope, name, scoped)
    if at == QNIL
      return zr_module_define_scoped_m(scope, name, scoped)
    end
    rec = Machine.slot(Frame.size)
    zr_walk_push(rec, at)
    r = zr_module_define_scoped_m(scope, name, scoped)
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  #: (value, value, value, value) -> value
  def zr_walk_const_set_m(at, klass, name, v)
    if at == QNIL
      return zr_const_set_m(klass, name, v)
    end
    rec = Machine.slot(Frame.size)
    zr_walk_push(rec, at)
    r = zr_const_set_m(klass, name, v)
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  # A `yield` of walked code to `blk` with the Array `args`, under a frame
  # of `at`, as zr_walk_send_m sends: a method whose body only yields
  # shows in a backtrace from the block. `keywords` is true when the last
  # element of `args` is a keyword Hash.
  #: (value, value, value, value) -> value
  def zr_walk_yield_m(at, blk, args, keywords)
    if keywords == QTRUE
      zr_kw_pass()
    end
    if at == QNIL
      return zr_yield(blk, RArray[args].len, RArray[args].ptr)
    end
    rec = Machine.slot(Frame.size)
    zr_walk_push(rec, at)
    r = zr_yield(blk, RArray[args].len, RArray[args].ptr)
    Task[zr_task()].top = Frame[rec].prev
    r
  end

  # Pushes `rec`, a Frame in the caller's stack, for `at` (`[meta, line,
  # self]`). The caller pops it.
  #: (ptr, value) -> void
  def zr_walk_push(rec, at)
    t = zr_task()
    meta = Machine.ptr(zr_fix2long(zr_ary_at(at, 0)))
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = meta
    Frame[rec].line = zr_fix2long(zr_ary_at(at, 1)) & WALK_LINE_MASK
    if FrameMeta[meta].evaled != 0
      Frame[rec].line = Frame[rec].line | WALK_EVAL_NODE
    end
    Frame[rec].serial = 0
    Frame[rec].self = zr_ary_at(at, 2)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].nvalues = 0
    Frame[rec].entry = 0
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
  end

  # The cref of a walked block that class_exec or instance_exec runs:
  # the crefs that the exec pushed (`eval`), over `outer`, the block's own
  # cref. Without it, they were over the walker's, so a `class` keyword
  # in the block defined its class in the walker's module.
  #: (value, value) -> value
  def zr_walk_cref_m(here, outer)
    if RCref[here].eval == 0
      return here
    end
    zr_walk_cref_onto(here, outer)
  end

  #: (value, value) -> value
  def zr_walk_cref_onto(here, outer)
    if RCref[here].eval == 0
      return outer
    end
    rest = zr_walk_cref_onto(RCref[here].next, outer)
    c = zr_cref_push(RCref[here].klass, rest)
    RCref[c].vis = RCref[here].vis
    RCref[c].modfn = RCref[here].modfn
    RCref[c].eval = RCref[here].eval
    RCref[c].entry = RCref[here].entry
    RCref[c].lazy = RCref[here].lazy
    c
  end

  # Eval support's own require (Hir::Require :hidden) from walked code:
  # the file that the program carries runs hidden from it, as compiled
  # code's require does (REQUIRE_KINDS `hidden`).
  #: (value) -> value
  def zr_walk_require_hidden_m(path)
    fn = zr_unit_for(path)
    if fn == QNIL
      return zr_load_error(RString[path].ptr, RString[path].len)
    end
    zr_require(path, Machine.ptr(zr_fix2long(fn)), 3)
  end

  # A frozen String literal of walked code, as the compiled literal gives
  # it (zr_str_literal_freeze and its kin): `kind` 0 is the interned String
  # of `text`; 1 the same unless the program redefined String#freeze, which
  # then runs; 2 the same for String#-@; 3 a frozen copy, not interned.
  #: (value, value) -> value
  def zr_walk_frozen_m(text, kind)
    copy = zr_str_exact_copy(zr_str_new(RString[text].ptr, RString[text].len), text)
    k = zr_fix2long(kind)
    if k == 1 && (Machine.gates & GATE_FREEZE) != 0
      return zr_send(copy, Machine.id(:freeze), 0, 0)
    end
    if k == 2 && (Machine.gates & GATE_STR_UMINUS) != 0
      return zr_send(copy, Machine.id(:-@), 0, 0)
    end
    if k == 3
      RBasic[copy].flags = RBasic[copy].flags | FL_FREEZE
      return copy
    end
    zr_str_intern(copy)
  end

  # debug_frozen_string_literal: a frozen copy of `text` that names
  # `file:line`, where it was made (zr_str_debug_frozen).
  #: (value, value, value) -> value
  def zr_walk_debug_string_m(text, file, line)
    copy = zr_str_exact_copy(zr_str_new(RString[text].ptr, RString[text].len), text)
    zr_str_created(copy, RString[file].ptr, RString[file].len, zr_fix2long(line))
    RBasic[copy].flags = RBasic[copy].flags | FL_FREEZE
    copy
  end
end
