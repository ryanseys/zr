module Zr::Kern
  # Call-site caches. Each compiled site that sends a message, reads a
  # constant, or reads or writes an instance variable has a cache entry in
  # `.bss`. The entry starts as zero and keeps the last result of its site.
  # The kernel fills and trusts every cache entry, so this file is the one
  # place that defines when a cached result is stale:
  #
  # - A send's cache entry is keyed on the receiver's class and the method
  #   stamp. Each change to a method table or an ancestor list increments
  #   the stamp (`zr_methods_changed`). The kernel fills the entry only when
  #   the class alone decides the result: no refinement is in use, the
  #   class has no box shadow, and the caller's self cannot change the
  #   visibility. The site checks the class and the stamp, then calls the
  #   entry's `fn` directly (`Zr::Lower::Function::Sends#cached_send`). The
  #   site stamp follows the method stamp while caches are on. It is -1
  #   while caches are off or verified, so every send goes through
  #   `zr_send_cached`.
  # - A constant's cache entry is keyed on the cref (or the scope of `A::B`)
  #   and on the constant stamp. The stamp changes on each constant write,
  #   removal and flag change, each ancestor list change, and each cref that
  #   the collector frees (its address can come back as another cref). The
  #   entry never contains an autoload, a deprecated constant, or a read
  #   made inside a box.
  # - A `case` on class arms has a table from the subject's class to the
  #   arm that the `when` chain selected. It is keyed on the cref and on
  #   both stamps, which it reads before the chain runs. The kernel adds a
  #   row only when the class alone decides the result: each arm that the
  #   chain tested read its constant from its cache entry and has
  #   Module#===, and the class has no box shadow (`zr_case_fill`).
  # - An instance variable's cache entry contains only a cached index: the
  #   ivar entry where the name was last time. Each use checks the name at
  #   that index, so the cache is never stale, only wrong. A wrong cached
  #   index costs one scan.
  #
  # `ZR_MCACHE=0` fills no cache entry. `ZR_MCACHE=verify` checks each hit
  # of a send or constant cache entry against a fresh lookup.
  class IvarCache < Layout
    attr_accessor :index #: word
  end
  # `found` is the ancestor list node that contains the method entry. A call
  # gives it to the frame, as a lookup does. `fn` is the function that a hit
  # calls, with the method signature for all entry kinds (`zr_entry_fn`).
  # A site has CALL_WAYS consecutive cache entries. The site checks the
  # first one itself. The kernel checks the others when the first misses,
  # so a site with receivers from a few classes gets a hit for each.
  # `shape` tells what a site can do in place of the call. SHAPE_READER and
  # SHAPE_WRITER: the site reads or writes an accessor's ivar itself
  # (`Zr::Lower::Function::Sends#accessor_in_place`), and so for a struct
  # member with SHAPE_STRUCT_READER and SHAPE_STRUCT_WRITER. The other shapes: the
  # site does one of the core's type checks itself (`#in_place`).
  # SHAPE_NONE is for all other kinds, and for a cache entry not yet filled.
  class CallCache < Layout
    attr_accessor :klass #: value
    attr_accessor :stamp #: word
    attr_accessor :entry #: ptr
    attr_accessor :found #: value
    attr_accessor :fn #: ptr
    attr_accessor :shape #: word
    attr_accessor :direct #: ptr
  end

  CALL_WAYS = 4
  SHAPE_NONE = 0
  SHAPE_READER = 1
  SHAPE_WRITER = 2
  SHAPE_IS_A = 3
  SHAPE_INSTANCE_OF = 4
  SHAPE_NIL_P = 5
  SHAPE_FROZEN_P = 6
  SHAPE_ARY_LENGTH = 7
  SHAPE_MOD_EQQ = 8
  # BasicObject's `==` (and `equal?`), and its `!=` when the class also
  # uses BasicObject's `==`. The site compares identity itself.
  SHAPE_EQ = 9
  SHAPE_NE = 10
  # Object's `===` when the class uses BasicObject's `==`. This is an
  # identity check, as in a `case` branch for a symbol, nil, true or false.
  SHAPE_EQQ = 11
  # The builtin Class#new. A `new` site allocates the object and sends
  # `initialize` itself (`Zr::Lower::Function::Sends#new_send`).
  SHAPE_NEW = 12
  # A struct member's reader and writer (lib/zr/runtime/kernel/struct.rb). The
  # site reads or writes the member in the values Array itself, through
  # the same guessed ivar entry as for an accessor.
  SHAPE_STRUCT_READER = 13
  SHAPE_STRUCT_WRITER = 14
  class ConstCache < Layout
    attr_accessor :key #: value
    attr_accessor :stamp #: word
    attr_accessor :value #: value
  end
  # The cache entry of a `super` site. The ancestor list node that the
  # method runs from and the name together decide the next method. The
  # entry keeps them and the lookup result for the method stamp
  # (lib/zr/runtime/kernel/send.rb, zr_super).
  class SuperCache < Layout
    attr_accessor :node #: value
    attr_accessor :mid #: word
    attr_accessor :stamp #: word
    attr_accessor :entry #: ptr
    attr_accessor :found #: value
    attr_accessor :fn #: ptr
  end
  # The cache entry of a `case` with class arms
  # (`Zr::Lower::Function::Control#class_case`). `table` has CASE_ROWS
  # rows of CaseRow, one for each class that hashes to it, and the kernel
  # allocates it on the first reset. `mstamp`, `cstamp` and `cref` tell
  # for which state the rows are valid. `proven` is the count of leading
  # `when` values that the kernel checked for that state: each read its
  # constant from its cache entry, and has Module#===. `due` is the index
  # of the value that the site gives to `zr_case_prove`, or -1 when a
  # value failed the check (a Range, or a class with its own `===`), so
  # the site stops calling the kernel for it.
  class CaseCache < Layout
    attr_accessor :mstamp #: word
    attr_accessor :cstamp #: word
    attr_accessor :cref #: value
    attr_accessor :table #: ptr
    attr_accessor :proven #: word
    attr_accessor :due #: word
  end
  # A row: the class of a subject, and the index of the arm (the count of
  # `when` clauses for `else`). A row with class 0 is empty.
  class CaseRow < Layout
    attr_accessor :klass #: value
    attr_accessor :arm #: word
  end

  CASE_ROWS = 32

  # Records a change that a constant lookup can see.
  #: () -> void
  def zr_consts_changed
    s = Machine.static(:const_stamp, 8)
    Machine.store64(s, 0, Machine.load64(s, 0) + 1)
  end

  # Returns the method entry that `cc` contains for a send of `mid` to
  # `recv`, or 0 when it has no valid one. A heap receiver's class comes
  # from its header, as in `zr_class_of`. A special constant's class comes
  # from `zr_class_of`. The task comes directly from its static word,
  # because every send goes through here.
  #: (ptr, value, word, word) -> ptr
  def zr_call_cache_hit(cc, recv, mid, mode)
    w = Machine.word(recv)
    if (w & 7) == 0 && w != QFALSE && w != QNIL
      klass = RBasic[recv].klass
    else
      klass = zr_class_of(recv)
    end
    if klass != CallCache[cc].klass || CallCache[cc].stamp != Machine.load64(Machine.static(:mcache_stamp, 8), 0)
      return 0
    end
    if Task[Machine.ptr(Machine.load64(Machine.static(:current_task, 16), 0))].refine != QNIL && (mode & SEND_USING) == 0
      return 0
    end
    e = CallCache[cc].entry
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY && e != zr_fresh_method(klass, mid)
      zr_bug(Machine.bytes("a call cache answered what the chain does not\n"), 46)
    end
    e
  end

  # Writes the method entry that `zr_dispatch` found for `klass` into the
  # cache entry, when the class and the stamp alone decided the result.
  #: (ptr, value, ptr, word, word, word) -> void
  def zr_call_cache_fill(cc, klass, e, mid, mode, argc)
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_OFF
      return
    end
    t = zr_task()
    if (Task[t].refine != QNIL && (mode & SEND_USING) == 0) || ClassExt[RClass[klass].ext].boxed != QNIL
      return
    end
    # For a private or protected method with an explicit receiver, the
    # caller decides the result, not the class.
    if (mode & SEND_MODE) >= 2 && MEntry[e].vis != VIS_PUBLIC
      return
    end
    # When the program redefines a method, a core send's entry is different
    # from the ancestor list's entry. The verifier reads the ancestor list,
    # so it leaves such a cache entry empty and does not report it as wrong.
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY && (mode & SEND_CORE) != 0 && e != zr_fresh_method(klass, mid)
      return
    end
    CallCache[cc].klass = klass
    CallCache[cc].stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
    CallCache[cc].entry = e
    CallCache[cc].found = zr_entry_found(e)
    CallCache[cc].fn = zr_entry_fn(e)
    CallCache[cc].shape = zr_entry_shape(klass, e)
    # The direct entry is for a site that gives the def exactly the
    # arguments that it declares. This does the checks of zr_direct_fn
    # one time, here.
    direct = 0
    if MEntry[e].kind == KIND_DEF && MEntry[e].arity == argc
      direct = MEntry[e].direct
    end
    CallCache[cc].direct = direct
  end

  # The generic entry of a def that has a direct entry. It checks the
  # keyword word and the argument count, as the def's prologue does, then
  # calls the body with the arguments in registers. A wrong count raises
  # under a frame of the def, as the prologue's check does, so the
  # backtrace shows the def.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_direct_fn(recv, argc, argv, e, blk, found)
    t = zr_task()
    kw = Task[t].kw
    if kw != 0
      Task[t].kw = 0
      argc = zr_kw_undeclared(kw, argc, argv, 0)
    end
    if argc != MEntry[e].arity
      return zr_direct_arity(recv, argc, e, blk, found)
    end
    direct = MEntry[e].direct
    if argc == 0
      return Direct0.call(direct, recv, e, blk, found)
    end
    a = Machine.value(Machine.load64(argv, 0))
    if argc == 1
      return Direct1.call(direct, recv, e, blk, found, a)
    end
    b = Machine.value(Machine.load64(argv, 8))
    if argc == 2
      return Direct2.call(direct, recv, e, blk, found, a, b)
    end
    c = Machine.value(Machine.load64(argv, 16))
    if argc == 3
      return Direct3.call(direct, recv, e, blk, found, a, b, c)
    end
    Direct4.call(direct, recv, e, blk, found, a, b, c, Machine.value(Machine.load64(argv, 24)))
  end

  # Raises the arity error of a def with a direct entry, under a frame of
  # the def: its meta, its line, its self and its block.
  #: (value, word, ptr, value, value) -> value
  def zr_direct_arity(recv, argc, e, blk, found)
    t = zr_task()
    rec = Machine.slot(Frame.size)
    if Machine.word(rec) < Machine.word(Task[t].stack_limit)
      return zr_stack_overflow()
    end
    meta = MEntry[e].meta
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = meta
    Frame[rec].line = (FrameMeta[meta].line & 4294967295) | (FrameMeta[meta].node << 32)
    Frame[rec].serial = 0
    Frame[rec].self = recv
    Frame[rec].cref = MEntry[e].cref
    Frame[rec].blk = blk
    Frame[rec].nvalues = 0
    Frame[rec].entry = e
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = found
    Task[t].top = rec
    r = zr_wrong_arity(argc, MEntry[e].arity)
    Task[t].top = Frame[rec].prev
    r
  end

  # Returns what a site can do in place of the call to `e`. For an
  # accessor, the site does the full body: one ivar read or write at the
  # cached index, which is all that `zr_attr_reader_fn` and
  # `zr_attr_writer_fn` do. For some core type checks, the builtin function
  # identifies the shape. The check is on the builtin, not the name: a
  # class that defines its own `is_a?` finds a different entry, and gets
  # SHAPE_NONE. `!=` is an identity check only when `klass` also uses
  # identity for `==`, because BasicObject's `!=` calls `==`.
  #: (value, ptr) -> word
  def zr_entry_shape(klass, e)
    kind = MEntry[e].kind
    if kind == KIND_ATTR_READER
      return SHAPE_READER
    end
    if kind == KIND_ATTR_WRITER
      return SHAPE_WRITER
    end
    if kind == KIND_STRUCT_AREF
      return SHAPE_STRUCT_READER
    end
    if kind == KIND_STRUCT_ASET
      return SHAPE_STRUCT_WRITER
    end
    if kind != KIND_BUILTIN
      return SHAPE_NONE
    end
    fn = MEntry[e].fn
    if fn == Machine.addr(:zr_obj_is_a)
      return SHAPE_IS_A
    end
    if fn == Machine.addr(:zr_obj_instance_of)
      return SHAPE_INSTANCE_OF
    end
    if fn == Machine.addr(:zr_obj_nil_p)
      return SHAPE_NIL_P
    end
    if fn == Machine.addr(:zr_obj_frozen_p)
      return SHAPE_FROZEN_P
    end
    if fn == Machine.addr(:zr_ary_length)
      return SHAPE_ARY_LENGTH
    end
    if fn == Machine.addr(:zr_mod_eqq)
      return SHAPE_MOD_EQQ
    end
    if fn == Machine.addr(:zr_obj_eq)
      return SHAPE_EQ
    end
    if fn == Machine.addr(:zr_class_new_instance)
      return SHAPE_NEW
    end
    if fn == Machine.addr(:zr_obj_ne) || fn == Machine.addr(:zr_obj_eqq)
      eq = zr_search_method(klass, Machine.id(:==))
      if eq != 0 && MEntry[eq].kind == KIND_BUILTIN && MEntry[eq].fn == Machine.addr(:zr_obj_eq)
        return fn == Machine.addr(:zr_obj_ne) ? SHAPE_NE : SHAPE_EQQ
      end
    end
    SHAPE_NONE
  end

  # `is_a?` at a site whose cache entry contains Kernel#is_a?, for a
  # receiver of class `klass`. When both are ranked classes (FL_RANKED),
  # one load of the rank gives the result, as in `zr_class_inherits`. In
  # all other cases this returns nil and the site calls the builtin. The
  # builtin builds the tables, walks a module's ancestor list, reads a
  # box's view, and raises for a value that is not a class or module. A
  # box shadow is in place of the shared class (`zr_is_a`), so a target
  # with a shadow also goes to the builtin. A site does the same checks
  # inline (`Sends#is_a_in_place`).
  #
  # Each check is on its own line with its own return. The lowering turns
  # an `||` expression into booleans, but these checks need one branch each.
  #: (value, value) -> value
  def zr_is_a_fast(klass, mod)
    w = Machine.word(mod)
    if (w & 7) != 0
      return Machine.value(QNIL)
    end
    if w <= QNIL
      return Machine.value(QNIL)
    end
    if (RBasic[mod].flags & FL_RANKED) == 0
      return Machine.value(QNIL)
    end
    if (RBasic[klass].flags & FL_RANKED) == 0
      return Machine.value(QNIL)
    end
    ext = RClass[klass].ext
    r = ClassExt[RClass[mod].ext].rank
    if r > ClassExt[ext].rank
      return Machine.value(QFALSE)
    end
    zr_bool(Machine.value(Machine.load64(ClassExt[ext].supers + ((r - 1) * 8), 0)) == mod)
  end

  # `mod === obj` at a site whose cache entry contains Module#===, which is
  # what `case obj when mod` calls. It returns `obj.is_a?(mod)` as the
  # builtin does (`zr_mod_eqq`), and never calls a method that `obj`
  # defines. A heap cell's class comes from its header. The class of any
  # other value comes from `zr_class_of`.
  #: (value, value) -> value
  def zr_mod_eqq_fast(mod, obj)
    w = Machine.word(obj)
    if (w & 7) == 0 && w > QUNDEF
      return zr_is_a_fast(RBasic[obj].klass, mod)
    end
    zr_is_a_fast(zr_class_of(obj), mod)
  end

  # Whether the cache entry of a `case` is valid for `cref` and for the
  # stamps `ms` and `cs`, which the site read before its `when` chain. If
  # the stamps are still current but the entry is for a different state,
  # this clears the entry for this state and returns true. If a stamp
  # changed during the chain (a definition, a collection, a constant
  # write), it returns false, and the chain's result is not for the
  # current state. A site stamp of -1 (caches off or verified) also gives
  # false, so no row goes into the table.
  #: (ptr, value, word, word) -> bool
  def zr_case_current(cc, cref, ms, cs)
    if ms == 0 - 1
      return false
    end
    if ms != Machine.load64(Machine.static(:site_stamp, 8), 0) || cs != Machine.load64(Machine.static(:const_stamp, 8), 0)
      return false
    end
    if CaseCache[cc].mstamp == ms && CaseCache[cc].cstamp == cs && CaseCache[cc].cref == cref
      return true
    end
    t = CaseCache[cc].table
    if t == 0
      t = zr_xmalloc(CASE_ROWS * CaseRow.size)
      CaseCache[cc].table = t
    end
    Libc.memset(t, Machine.i32(0), CASE_ROWS * CaseRow.size)
    CaseCache[cc].mstamp = ms
    CaseCache[cc].cstamp = cs
    CaseCache[cc].cref = cref
    CaseCache[cc].proven = 0
    CaseCache[cc].due = 0
    true
  end

  # Checks `v`, the `when` value at index `j`, which the site read from its
  # constant's cache entry. The site calls this only when `j` is the
  # entry's `due` index, so the values are checked in order. A value that
  # passes is a module or class with no box shadow, and its `===` is
  # Module#===. Thus `v === subject` is `subject.is_a?(v)`, which only the
  # subject's class decides, and which calls no method of the program.
  # A value that fails stops the checks until the state changes.
  #: (ptr, value, value, word, word, word) -> void
  def zr_case_prove(cc, cref, v, j, ms, cs)
    if !zr_case_current(cc, cref, ms, cs) || j != CaseCache[cc].due
      return
    end
    if zr_case_plain_arm(v)
      CaseCache[cc].proven = j + 1
      CaseCache[cc].due = j + 1
    else
      CaseCache[cc].due = 0 - 1
    end
  end

  # Whether `mod === obj` is `obj.is_a?(mod)` for each `obj`: `mod` is a
  # module or class that is not a box shadow, its own class has no box
  # shadow, and the lookup of `===` finds the builtin Module#===. A class
  # that defines `self.===` (SystemCallError, or a program's class), a
  # prepended `===`, or a redefined Module#=== fails. Under a refinement,
  # the lookup can differ from site to site, so that also fails.
  #: (value) -> bool
  def zr_case_plain_arm(mod)
    if !zr_module_p(mod) || zr_box_origin(mod) != QNIL
      return false
    end
    if Task[zr_task()].refine != QNIL
      return false
    end
    k = zr_class_of(mod)
    if ClassExt[RClass[k].ext].boxed != QNIL
      return false
    end
    e = zr_search_method(k, Machine.id(:===))
    e != 0 && MEntry[e].kind == KIND_BUILTIN && MEntry[e].fn == Machine.addr(:zr_mod_eqq)
  end

  # Adds the row `klass` => `arm` after the `when` chain selected `arm`
  # for a subject of class `klass`. `count` is how many `when` values the
  # chain tested. Each of them must be proven (`zr_case_prove`), because
  # then each one's result depends only on `klass`. The site finds the row
  # by the same hash (`Control#case_row`). A class with a box shadow, a
  # read in a box, a ractor and a refinement in use each give no row,
  # because the chain's result can differ for them.
  #: (ptr, value, value, word, word, word, word) -> void
  def zr_case_fill(cc, cref, klass, arm, count, ms, cs)
    if !zr_case_current(cc, cref, ms, cs) || count > CaseCache[cc].proven
      return
    end
    if ClassExt[RClass[klass].ext].boxed != QNIL || zr_box_current() != QNIL
      return
    end
    t = zr_task()
    if Task[t].ractor != 0 || Task[t].refine != QNIL
      return
    end
    w = Machine.word(klass)
    row = CaseCache[cc].table + ((((w / CELL_MIN) ^ (w / (CELL_MIN * CASE_ROWS))) & (CASE_ROWS - 1)) * CaseRow.size)
    CaseRow[row].klass = klass
    CaseRow[row].arm = arm
  end

  # `instance_of?` at a site whose cache entry contains
  # Kernel#instance_of?, for a receiver of class `klass`. It checks whether
  # the real class is `c`. The real class skips a singleton class and the
  # proxies of extended modules (`zr_real_class`). It returns nil when `c`
  # is not a class or module, because the builtin raises for that.
  #: (value, value) -> value
  def zr_instance_of_fast(klass, c)
    if !zr_module_p(c) || !zr_class_inherits(klass, zr_global(G_OBJECT))
      return Machine.value(QNIL)
    end
    k = klass
    while zr_singleton_p(k) || zr_type(k) == T_ICLASS
      k = RClass[k].superclass
    end
    zr_bool(k == c)
  end

  # Returns the function that a hit on entry `e` calls with the method
  # signature. For a compiled def, it is the def. For an accessor, it is
  # the accessor's function. For all other kinds, it runs the dispatch
  # steps, which push the frame and check the arity.
  #: (ptr) -> ptr
  def zr_entry_fn(e)
    kind = MEntry[e].kind
    if kind == KIND_DEF
      return MEntry[e].fn
    end
    if kind == KIND_BUILTIN
      return Machine.addr(:zr_builtin_fn)
    end
    if kind == KIND_ATTR_READER
      return Machine.addr(:zr_attr_reader_fn)
    end
    if kind == KIND_ATTR_WRITER
      return Machine.addr(:zr_attr_writer_fn)
    end
    if kind == KIND_BMETHOD
      # The twin of the body block, if it has one (FrameMeta).
      if MEntry[e].fn != 0
        return MEntry[e].fn
      end
      return Machine.addr(:zr_bmethod_fn)
    end
    if kind == KIND_STRUCT_AREF
      return Machine.addr(:zr_struct_aref_fn)
    end
    if kind == KIND_STRUCT_ASET
      return Machine.addr(:zr_struct_aset_fn)
    end
    Machine.addr(:zr_invoke_fn)
  end

  # Runs a hit on an entry that is not a compiled def, as a dispatch does.
  # It takes a keywords Hash that the site flagged, as the dispatch does.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_invoke_fn(recv, argc, argv, e, blk, found)
    Task[zr_task()].found = found
    zr_invoke(e, recv, argc, argv, blk, zr_kw_take())
  end

  # Runs a hit on a builtin entry. It does only the dispatch steps for a
  # builtin (lib/zr/runtime/kernel/send.rb, zr_invoke), with no kind check. First,
  # a keyword table becomes one Hash argument. The frame that it pushes
  # shows the builtin in a backtrace and does the stack check of a compiled
  # prologue. The arity check runs under that frame.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_builtin_fn(recv, argc, argv, e, blk, found)
    t = zr_task()
    Task[t].found = found
    kw = Task[t].kw
    if kw > 1
      argc = zr_kw_tab_in(kw, argc, argv)
      kw = zr_kw_hashed(kw)
    end
    rec = Machine.slot(Frame.size)
    if Machine.word(rec) < Machine.word(Task[t].stack_limit)
      return zr_stack_overflow()
    end
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = MEntry[e].meta
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].self = recv
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = blk
    Frame[rec].nvalues = 0
    Frame[rec].entry = e
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    Task[t].kw = kw
    arity = MEntry[e].arity
    if arity >= 0 && argc != arity
      r = zr_wrong_arity(argc, arity)
    else
      r = Builtin.call(MEntry[e].fn, recv, argc, argv, Machine.value(QNIL), blk)
    end
    Task[t].kw = 0
    Task[t].top = Frame[rec].prev
    r
  end

  # An accessor has no frame, so its arity error comes from the caller.
  # The entry's `fn` contains the ivar's id, and the entry has its own
  # cached index.
  #
  # This reads the ivar entry at the cached index directly, and does not
  # call `zr_ivar_get_cached` (which calls `zr_ivar_row_guessed`). A site
  # that reads its own `@name` checks the cached index inline (the
  # lowering's `guessed_ivar_row`). Through a reader call, a site pays for
  # the same three loads plus two calls. A profile of bm_attr_accessor had
  # 261 of 389 samples in these three frames, 131 in `zr_ivar_row_guessed`
  # alone. Only a receiver that the cached index does not resolve (a class,
  # a module, a special constant, a ractor's object, a wrong cached index)
  # goes on to the kernel's read, which updates the cached index.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_attr_reader_fn(recv, argc, argv, e, blk, found)
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    t = zr_task()
    Task[t].kw = 0
    id = Machine.word(MEntry[e].fn)
    ic = Machine.ptr(MEntry[e].ivar)
    w = Machine.word(recv)
    if (w & 7) == 0 && w > QNIL && (RBasic[recv].flags & T_MASK) == T_OBJECT && Task[t].ractor == 0
      row = zr_ivar_guess_row(Machine.ptr(RObject[recv].iv), id, ic)
      if row != 0
        v = IvEntry[row].value
        return v == QUNDEF ? Machine.value(QNIL) : v
      end
    end
    zr_ivar_get_cached(recv, id, ic)
  end

  # The type check also checks the frozen bit, as in `zr_ivar_set_cached`.
  # A frozen receiver is not a plain unfrozen object, so it goes to the
  # kernel's write, which raises at the caller's line.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_attr_writer_fn(recv, argc, argv, e, blk, found)
    if argc != 1
      return zr_wrong_arity(argc, 1)
    end
    t = zr_task()
    Task[t].kw = 0
    id = Machine.word(MEntry[e].fn)
    ic = Machine.ptr(MEntry[e].ivar)
    v = Machine.value(Machine.load64(argv, 0))
    w = Machine.word(recv)
    if (w & 7) == 0 && w > QNIL && (RBasic[recv].flags & (T_MASK | FL_FREEZE)) == T_OBJECT && Task[t].ractor == 0
      row = zr_ivar_guess_row(Machine.ptr(RObject[recv].iv), id, ic)
      if row != 0
        IvEntry[row].value = v
        zr_write_barrier(recv, v)
        return v
      end
    end
    zr_ivar_set_cached(recv, id, v, ic)
  end

  # Returns the ivar entry of table `t` at the cached index in `ic`, when
  # the table is long enough and that entry contains `id`. Otherwise it
  # returns 0. This is the part of `zr_ivar_row_guessed` after it finds the
  # table. It is small, so an accessor contains a copy in place of a call.
  #: (ptr, word, ptr) -> ptr
  def zr_ivar_guess_row(t, id, ic)
    i = IvarCache[ic].index
    if i >= IvTab[t].len
      return 0
    end
    e = IvTab[t].rows + (i * IvEntry.size)
    IvEntry[e].id == id ? e : 0
  end

  # A send through the site's cache entries, when the site's own check
  # did not hit (a special constant, a stale cache entry, a refinement in
  # use, caches off or verified). A hit calls the entry's `fn`. A miss does
  # a dispatch, which fills a cache entry.
  #: (ptr, value, word, word, ptr, value, word) -> value
  def zr_send_cached(cc, recv, mid, argc, argv, blk, mode)
    using = (mode & SEND_USING) != 0
    if Task[zr_task()].refine == QNIL || using
      # Read the class and the stamp one time, then check each way. The
      # site already checked the first way for all receivers, so this
      # checks the other ways. Under ZR_MCACHE=verify, no site check hits,
      # so this checks the first way too, and verifies each hit against
      # the ancestor list. A site under `using` checks no way itself. Its
      # cache entries contain the lookup results under its refinements.
      w = Machine.word(recv)
      verify = Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
      if (w & 7) == 0 && w > QUNDEF
        klass = RBasic[recv].klass
      elsif (w & 1) != 0
        klass = zr_global(G_INTEGER)
      else
        klass = zr_class_of(recv)
      end
      i = verify || using ? 0 : 1
      stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
      while i < CALL_WAYS
        way = cc + (i * CallCache.size)
        if CallCache[way].klass == klass && CallCache[way].stamp == stamp
          e = CallCache[way].entry
          if verify && e != zr_fresh_method(klass, mid)
            zr_bug(Machine.bytes("a call cache answered what the chain does not\n"), 46)
          end
          r = Method.call(CallCache[way].fn, recv, argc, argv, e, blk, CallCache[way].found)
          # The site activated the refinements for this send only, so clear
          # them, as zr_dispatch does.
          if using
            Task[zr_task()].refine = Machine.value(QNIL)
          end
          return r
        end
        i += 1
      end
    end
    zr_dispatch(zr_call_cache_slot(cc), recv, mid, argc, argv, mode, blk)
  end

  # Returns the method entry from the ancestor list, with no cache. It
  # uses the active refinements, or a plain lookup when there are none.
  #: (value, word) -> ptr
  def zr_fresh_method(klass, mid)
    if Task[zr_task()].refine != QNIL
      return zr_refined_search(klass, mid)
    end
    zr_search_method(klass, mid)
  end

  # Returns the cache entry that a dispatch fills: the first empty or
  # stale one, else the last. Thus the class that the site checks itself
  # keeps the first way.
  #: (ptr) -> ptr
  def zr_call_cache_slot(cc)
    i = 0
    while i < CALL_WAYS - 1
      way = cc + (i * CallCache.size)
      if CallCache[way].klass == 0 || CallCache[way].stamp != Machine.load64(Machine.static(:mcache_stamp, 8), 0)
        return way
      end
      i += 1
    end
    cc + ((CALL_WAYS - 1) * CallCache.size)
  end

  # A `new` call, as CRuby's `opt_new` (and a `new` with a block, which
  # `Class#new` gives to `initialize`). It has cache entries for each of
  # its two lookups: `new` on the receiver's class, then `initialize` on
  # the new object. When the lookup finds the public builtin `Class#new`,
  # it runs with no frame, so a backtrace goes from `initialize` directly
  # to the caller. Any other `new` is a send through the cache entry that
  # the lookup filled.
  #: (ptr, value, word, ptr, value, word) -> value
  def zr_new_cached(cc, recv, argc, argv, blk, mode)
    e = zr_call_cache_hit(cc, recv, Machine.id(:new), mode)
    if e == 0
      klass = zr_box_view(zr_class_of(recv))
      e = zr_find_method(klass, Machine.id(:new))
      if e != 0
        zr_call_cache_fill(cc, klass, e, Machine.id(:new), mode, 0 - 2)
      end
    end
    # `Array.new` and `String.new` have their own method entries
    # (zr_class_s_new), so a program's backtrace includes them. A `new`
    # with a block is a call of `Class#new` with a frame, because opt_new
    # applies only without a block. A `new` from the core library is like
    # C's rb_ary_new or rb_class_new_instance, with no frame, so it always
    # takes the fast path below.
    core = (mode & SEND_CORE) != 0
    plain = e != 0 && (blk == QNIL || core) && (MEntry[e].fn == Machine.addr(:zr_class_new_instance) || (core && MEntry[e].fn == Machine.addr(:zr_class_s_new)))
    if !plain || MEntry[e].vis != VIS_PUBLIC
      return zr_send_cached(cc, recv, Machine.id(:new), argc, argv, blk, mode)
    end
    o = zr_class_new_object(recv)
    return o if o == QUNDEF
    # `initialize` is private, so this is an implicit send. A `new` from
    # the core library keeps SEND_CORE, so it finds the core's own method
    # entry when the program redefines it (`Array.new` in the core is
    # rb_ary_new, which runs no program's initialize).
    r = zr_send_cached(cc + (CallCache.size * CALL_WAYS), o, Machine.id(:initialize), argc, argv, blk, mode & (SEND_USING | SEND_CORE))
    return r if r == QUNDEF
    o
  end

  # Whether a cache entry can contain the value of constant entry `e`. The
  # value must be set (not an autoload still to run), not deprecated (each
  # read warns), and read outside a box (a box sees its own constant
  # entries and classes). While a task reads the name's autoload file, a
  # value that the file set is that task's own, and other tasks wait for
  # the file, so no site keeps it yet.
  #: (ptr) -> bool
  def zr_const_cacheable(e)
    CEntry[e].value != QUNDEF && CEntry[e].deprecated == 0 && zr_box_current() == QNIL && !zr_autoload_running(CEntry[e].owner, CEntry[e].id)
  end

  # `stamp` is the value read before the lookup. Thus, a change that the
  # lookup causes makes the cache entry stale immediately.
  #: (ptr, value, word, value) -> void
  def zr_const_cache_fill(cc, key, stamp, v)
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_OFF
      return
    end
    ConstCache[cc].key = key
    ConstCache[cc].stamp = stamp
    ConstCache[cc].value = v
  end

  # `ZR_MCACHE=verify`: checks that the constant entry from a fresh lookup
  # contains the value that the cache entry returned.
  #: (ptr, ptr) -> void
  def zr_const_cache_verify(cc, e)
    if e == 0 || !zr_const_cacheable(e) || CEntry[e].value != ConstCache[cc].value
      zr_bug(Machine.bytes("a constant cache answered what the lookup does not\n"), 51)
    end
  end

  # Reads a bare constant under `cref` at a site. Returns the same value as
  # `zr_const_get`.
  #: (ptr, value, word) -> value
  def zr_const_get_cached(cc, cref, id)
    stamp = Machine.load64(Machine.static(:const_stamp, 8), 0)
    if ConstCache[cc].key == cref && ConstCache[cc].stamp == stamp
      if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
        zr_const_cache_verify(cc, zr_const_row_under(cref, id))
      end
      return ConstCache[cc].value
    end
    e = zr_const_row_under(cref, id)
    if e != 0 && zr_const_cacheable(e)
      zr_const_cache_fill(cc, cref, stamp, CEntry[e].value)
      return CEntry[e].value
    end
    zr_const_get(cref, id)
  end

  # Reads a program's bare constant. Outside the main ractor, the value
  # must be shareable. There, the cache entry is not used, so each read does
  # a lookup (the stamp changes when a ractor's task starts and stops).
  #: (ptr, value, word) -> value
  def zr_const_read_cached(cc, cref, id)
    if Task[zr_task()].ractor == 0
      return zr_const_get_cached(cc, cref, id)
    end
    v = zr_const_get(cref, id)
    return v if v == QUNDEF
    e = zr_const_row_under(cref, id)
    if e == 0
      return v
    end
    zr_ractor_const(CEntry[e].owner, id, v)
  end

  # Reads a program's `scope::Name` in the same way.
  #: (ptr, value, word) -> value
  def zr_const_read_at_cached(cc, scope, id)
    if Task[zr_task()].ractor == 0
      return zr_const_get_at_cached(cc, scope, id)
    end
    v = zr_const_get_at(scope, id)
    return v if v == QUNDEF
    if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
      return v
    end
    e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
    if e == 0
      return v
    end
    zr_ractor_const(CEntry[e].owner, id, v)
  end

  # Checks `v`, a constant of `owner`, read outside the main ractor. The
  # ractor can read it only if it is shareable.
  #: (value, word, value) -> value
  def zr_ractor_const(owner, id, v)
    if zr_special_p(v)
      return v
    end
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.word(owner))
    Machine.store64(args, 8, Machine.word(zr_sym(id)))
    Machine.store64(args, 16, Machine.word(v))
    zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:const_read), 3, args)
  end

  # Reads `scope::Name` at a site. Returns the same value as
  # `zr_const_get_at`. A private constant raises each time, so its constant
  # entry never goes into the cache entry.
  #: (ptr, value, word) -> value
  def zr_const_get_at_cached(cc, scope, id)
    stamp = Machine.load64(Machine.static(:const_stamp, 8), 0)
    if ConstCache[cc].key == scope && ConstCache[cc].stamp == stamp
      if Machine.load64(Machine.static(:mcache_mode, 8), 0) == MCACHE_VERIFY
        zr_const_cache_verify(cc, zr_const_row_in(scope, id, scope != zr_global(G_OBJECT)))
      end
      return ConstCache[cc].value
    end
    if !zr_special_p(scope) && (zr_type(scope) == T_CLASS || zr_type(scope) == T_MODULE)
      e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
      if e != 0 && CEntry[e].private == 0 && zr_const_cacheable(e)
        zr_const_cache_fill(cc, scope, stamp, CEntry[e].value)
        return CEntry[e].value
      end
    end
    zr_const_get_at(scope, id)
  end

  # Reads `@name` at a site with the cached index `ic`. Returns the same
  # value as `zr_ivar_get`.
  #: (value, word, ptr) -> value
  def zr_ivar_get_cached(obj, id, ic)
    e = zr_ivar_row_guessed(obj, id, ic)
    if e != 0
      v = IvEntry[e].value
      return v == QUNDEF ? Machine.value(QNIL) : v
    end
    g = zr_ractor_guard(obj)
    if g == QUNDEF
      return g
    end
    t = zr_ivtab(obj)
    if t == 0
      return Machine.value(QNIL)
    end
    e = zr_ivtab_guess(t, id, ic)
    if e == 0 || IvEntry[e].value == QUNDEF
      return Machine.value(QNIL)
    end
    IvEntry[e].value
  end

  # Writes `@name = v` at a site with the cached index `ic`. Does the same
  # as `zr_ivar_set`.
  #: (value, word, value, ptr) -> value
  def zr_ivar_set_cached(obj, id, v, ic)
    e = zr_ivar_row_guessed(obj, id, ic)
    if e != 0 && (RBasic[obj].flags & FL_FREEZE) == 0
      IvEntry[e].value = v
      zr_write_barrier(obj, v)
      return v
    end
    # A plain object outside a ractor, not frozen, whose cached index is
    # one past its last ivar entry. This is the first assignment in an
    # `initialize`. When no entry contains `id`, the new entry goes at the
    # end, with no more kernel calls.
    if !zr_special_p(obj) && (RBasic[obj].flags & (T_MASK | FL_FREEZE)) == T_OBJECT && Task[zr_task()].ractor == 0
      t = Machine.ptr(RObject[obj].iv)
      if IvarCache[ic].index == IvTab[t].len && zr_ivtab_row(t, id) == 0
        zr_ivtab_append(t, id, v, obj)
        zr_write_barrier(obj, v)
        return v
      end
    end
    g = zr_ractor_guard(obj)
    if g == QUNDEF
      return g
    end
    if zr_modify_frozen_p(obj)
      return zr_frozen_error(obj)
    end
    t = zr_ivtab_for_write(obj)
    e = zr_ivtab_guess(t, id, ic)
    if e == 0
      # A new ivar entry goes at the end, where the next cached index finds it.
      IvarCache[ic].index = IvTab[t].len
      zr_ivtab_set_in(t, id, v, zr_ivtab_owner(obj))
    else
      IvEntry[e].value = v
    end
    zr_write_barrier(obj, v)
    v
  end

  # Returns the ivar entry at the cached index in the table of an object,
  # class or module, when that entry contains `id` and the read is outside
  # a ractor (`zr_ractor_guard` applies the ractor isolation rule).
  # Otherwise it returns 0. A site does this check inline before it calls
  # here (the lowering's `guessed_ivar_row`). An accessor entry calls here
  # directly.
  #: (value, word, ptr) -> ptr
  def zr_ivar_row_guessed(obj, id, ic)
    if zr_special_p(obj) || Task[zr_task()].ractor != 0
      return 0
    end
    kind = RBasic[obj].flags & T_MASK
    if kind == T_OBJECT
      t = Machine.ptr(RObject[obj].iv)
    elsif kind == T_CLASS || kind == T_MODULE
      t = Machine.ptr(ClassExt[RClass[obj].ext].iv)
    else
      return 0
    end
    zr_ivar_guess_row(t, id, ic)
  end

  # Returns the ivar entry for `id` in the table `t`, or 0. It first tries
  # the cached index. Otherwise a scan finds the entry, and its index
  # becomes the new cached index.
  #: (ptr, word, ptr) -> ptr
  def zr_ivtab_guess(t, id, ic)
    i = IvarCache[ic].index
    if i < IvTab[t].len
      e = IvTab[t].rows + (i * IvEntry.size)
      if IvEntry[e].id == id
        return e
      end
    end
    e = zr_ivtab_row(t, id)
    if e != 0
      IvarCache[ic].index = (Machine.word(e) - Machine.word(IvTab[t].rows)) / IvEntry.size
    end
    e
  end
end
