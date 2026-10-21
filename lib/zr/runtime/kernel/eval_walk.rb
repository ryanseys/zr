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
  # Integer, or nil. `evaled` is true for code with no absolute path.
  #: (value, value, value, value, value, value) -> value
  def zr_walk_meta_m(kind, name, owner, file, parent, evaled)
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
  # plus WALK_KEYWORDS when the last element of `args` is a keyword Hash.
  WALK_KEYWORDS = 256
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
    if at == QNIL
      return zr_dispatch(0, recv, zr_sym2id(name), RArray[args].len, RArray[args].ptr, m, blk)
    end
    rec = Machine.slot(Frame.size)
    t = zr_task()
    Frame[rec].prev = Task[t].top
    meta = Machine.ptr(zr_fix2long(zr_ary_at(at, 0)))
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
    r = zr_dispatch(0, recv, zr_sym2id(name), RArray[args].len, RArray[args].ptr, m, blk)
    Task[t].top = Frame[rec].prev
    r
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
end
