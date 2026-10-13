module Zr::Kern
  # Constants and the lexical scope list. A cref cell refers to a class and
  # to the cref outside it. The toplevel cref refers to Object alone. A
  # constant read looks through the lexical scope list first (Object last,
  # and only as an ancestor), then the ancestors of the innermost class.
  # `vis` is the visibility (VIS_*) that a def under the cref gets, and
  # `modfn` is whether `module_function` is on.
  # `class_eval`, `instance_eval` and `Class.new` push a cref with `eval`
  # set. A `def` defines its method there, but constants and class
  # variables skip that cref and use the lexical scope. The cref of a
  # method from `define_method` refers to its method entry, and `super` in
  # the body resolves from that entry.
  # `lazy` is the object that an `instance_exec` runs under, until some
  # code needs its singleton class. ruby makes that class only then, and an
  # object with a singleton class shows differently in an error message.
  class RCref < Layout
    attr_reader :basic #: RBasic
    attr_accessor :klass #: value
    attr_accessor :next #: value
    attr_accessor :vis #: word
    attr_accessor :modfn #: word
    attr_accessor :eval #: word
    attr_accessor :entry #: ptr
    attr_accessor :lazy #: value
  end

  T_CREF = 25
  # The `RCref.eval` value for a block that runs under an object with no
  # singleton class, as in `1.instance_eval`. A `def` there has no class to
  # define the method on.
  EVAL_NO_DEF = 2
  VIS_PUBLIC = 0
  VIS_PRIVATE = 1
  VIS_PROTECTED = 2
  G_TOP_CREF = 24

  #: (value, value) -> value
  def zr_cref_push(klass, outer)
    c = zr_alloc(T_CREF, Machine.value(QNIL), RCref.size)
    RCref[c].klass = klass
    RCref[c].next = outer
    RCref[c].vis = VIS_PUBLIC
    RCref[c].modfn = 0
    RCref[c].eval = 0
    RCref[c].entry = 0
    RCref[c].lazy = Machine.value(QNIL)
    c
  end

  # Returns the class of a cref. If the cref is for the singleton class of
  # an object and no code needed that class yet, it makes the class first.
  #: (value) -> value
  def zr_cref_klass(cref)
    obj = RCref[cref].lazy
    if obj != QNIL
      RCref[cref].klass = zr_singleton_class(obj)
      RCref[cref].lazy = Machine.value(QNIL)
    end
    RCref[cref].klass
  end

  # The class that `alias` and `undef` change: the cref's class. Under
  # `1.instance_eval` there is none, as in CRuby's singleton_class_for_eval.
  #: (value) -> value
  def zr_cref_definee(cref)
    if RCref[cref].eval == EVAL_NO_DEF
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
    end
    zr_cref_klass(cref)
  end

  #: (value, value) -> value
  def zr_cref_push_eval(klass, outer)
    c = zr_cref_push(klass, outer)
    RCref[c].eval = 1
    c
  end

  # Whether two Values are the same object, without a method call on
  # either. A cref has no class, so `equal?` on a cref cannot dispatch. The
  # tree-walking interpreter keeps crefs and must tell them apart.
  #: (value, value) -> value
  def zr_same_p(a, b)
    zr_bool(a == b)
  end

  # A bare `private`, `public`, `protected` or `module_function` in a class
  # body sets the visibility of that body, which is in its cref. Compiled
  # code writes it where the body runs. The tree-walking interpreter has the
  # cref but no frame of the body to write it in, so it writes it here.
  # 0 is public, 1 is private, 2 is protected.
  #: (value, value) -> value
  def zr_cref_set_vis(cref, vis)
    RCref[cref].vis = zr_fix2long(vis)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_cref_set_modfn(cref)
    RCref[cref].modfn = 1
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_cref_lexical(cref)
    while RCref[cref].eval != 0
      cref = RCref[cref].next
    end
    cref
  end

  # The class whose constants a lookup reads at `cref`: the class, or for
  # an object whose singleton class is not made yet, the object's class.
  #: (value) -> value
  def zr_cref_lookup_class(cref)
    obj = RCref[cref].lazy
    obj != QNIL ? zr_class_of(obj) : zr_cref_klass(cref)
  end

  #: (value) -> value
  def zr_cref_lexical_class(cref)
    zr_cref_klass(zr_cref_lexical(cref))
  end

  # A constant table of this length or more has a hash index of its ids.
  # The first lookup that needs the index builds it. Object's table has
  # hundreds of entries, and every bare constant read ends there. A lookup
  # scans a shorter table.
  CONST_INDEX_MIN = 16

  # Deletes the index. The next lookup that needs it builds it again.
  #: (ptr) -> void
  def zr_const_index_drop(ext)
    if ClassExt[ext].cidx != 0
      zr_xfree(ClassExt[ext].cidx)
      ClassExt[ext].cidx = 0
    end
  end

  # Adds entry number `row` to the index. A bin contains the entry number
  # plus one, or zero when empty. Entries go in in order, so when two
  # entries have the same id, the lookup finds the earlier one first, as a
  # scan does.
  #: (ptr, word) -> void
  def zr_const_index_put(ext, row)
    mask = ClassExt[ext].cbins - 1
    h = Machine.mul_wrap(CEntry[ClassExt[ext].ctab + (row * CEntry.size)].id, 2654435761) & mask
    while Machine.load64(ClassExt[ext].cidx + (h * 8), 0) != 0
      h = (h + 1) & mask
    end
    Machine.store64(ClassExt[ext].cidx + (h * 8), 0, row + 1)
  end

  # Builds a new index of all entries, with at least four bins for each entry.
  #: (ptr) -> void
  def zr_const_index_build(ext)
    zr_const_index_drop(ext)
    n = ClassExt[ext].clen
    bins = 64
    while bins < n * 4
      bins = bins * 2
    end
    ClassExt[ext].cidx = zr_xmalloc(bins * 8)
    Libc.memset(ClassExt[ext].cidx, Machine.i32(0), bins * 8)
    ClassExt[ext].cbins = bins
    i = 0
    while i < n
      zr_const_index_put(ext, i)
      i += 1
    end
  end

  # Adds a new last entry to the index while the bins stay less than half
  # full. Otherwise it deletes the index, and the next lookup builds a
  # larger one.
  #: (ptr, word) -> void
  def zr_const_index_add(ext, row)
    if ClassExt[ext].cidx == 0
      return
    end
    if (row + 1) * 2 > ClassExt[ext].cbins
      zr_const_index_drop(ext)
      return
    end
    zr_const_index_put(ext, row)
  end

  # Returns the entry number of `id` in the table, or -1.
  #: (ptr, word) -> word
  def zr_const_index_find(ext, id)
    if ClassExt[ext].cidx == 0
      zr_const_index_build(ext)
    end
    mask = ClassExt[ext].cbins - 1
    h = Machine.mul_wrap(id, 2654435761) & mask
    slot = Machine.load64(ClassExt[ext].cidx + (h * 8), 0)
    while slot != 0
      if CEntry[ClassExt[ext].ctab + ((slot - 1) * CEntry.size)].id == id
        return slot - 1
      end
      h = (h + 1) & mask
      slot = Machine.load64(ClassExt[ext].cidx + (h * 8), 0)
    end
    0 - 1
  end

  # Returns the constant entry for `id` on `klass` alone, or 0. The program
  # cannot read an entry that the runtime hides.
  #: (value, word) -> ptr
  def zr_const_row(klass, id)
    e = zr_const_row_kept(klass, id)
    if e != 0 && CEntry[e].concealed != 0 && !zr_const_sees_concealed()
      return 0
    end
    e
  end

  # Constants of Object that a file set, when only the runtime loads that
  # file, for example Zr and Prism from eval support. They stay hidden from
  # the program, because ruby has neither, until the program requires the
  # file itself. Three kinds of code can read them: code of a unit that
  # loads hidden, the runtime's own code, and any code that runs while a
  # hidden file loads. A reflective read, such as const_get, reads as the
  # frame that called the core library, unless the core library itself
  # asked (File.fnmatch reads its Dir::Glob with const_get).
  #: () -> bool
  def zr_const_sees_concealed
    if zr_loading_hidden()
      return true
    end
    # The tree-walking interpreter reads a constant for the program that
    # it walks (`zr_walk_const`): it sees what compiled code there sees.
    if Machine.load64(Machine.static(:const_for_program, 8), 0) > 0
      return false
    end
    rec = Task[zr_task()].top
    reflective = Machine.load64(Machine.static(:const_reflective, 8), 0) > 0
    if !reflective && rec != 0 && (FrameMeta[Frame[rec].meta].kind == KIND_BUILTIN || FrameMeta[Frame[rec].meta].kind == KIND_HIDDEN)
      return true
    end
    asking = zr_asking_frame()
    if reflective && asking != 0 && zr_core_asks_reflectively(rec, asking)
      return true
    end
    asking == 0 || FrameMeta[Frame[asking].meta].hidden != 0
  end

  # Whether the core method that frame `asking` called, the frame just
  # above it from `top`, is another method than the reflective one: then
  # that core method asks, as the runtime's own code.
  #: (ptr, ptr) -> bool
  def zr_core_asks_reflectively(top, asking)
    above = 0
    rec = top
    while rec != 0 && rec != asking
      above = rec
      rec = Frame[rec].prev
    end
    if above == 0
      return false
    end
    name = FrameMeta[Frame[above].meta].name
    name != Machine.id(:const_get) && name != Machine.id(:constants) && name != Machine.id(:const_defined?) &&
      name != Machine.id(:const_source_location) && name != Machine.id(:send) && name != Machine.id(:__send__) &&
      name != Machine.id(:public_send) && name != Machine.id(:call)
  end

  # Whether a reflective read, such as Module#constants, sees a hidden
  # constant entry.
  #: () -> bool
  def zr_const_sees_reflectively
    depth = Machine.static(:const_reflective, 8)
    Machine.store64(depth, 0, Machine.load64(depth, 0) + 1)
    sees = zr_const_sees_concealed()
    Machine.store64(depth, 0, Machine.load64(depth, 0) - 1)
    sees
  end

  # Makes Object's constant `id` visible. A hidden file defined or reopened
  # it, and now the program required that file itself.
  #: (word) -> void
  def zr_const_reveal(id)
    e = zr_const_row_kept(zr_global(G_OBJECT), id)
    if e != 0 && CEntry[e].concealed != 0
      CEntry[e].concealed = 0
      zr_consts_changed()
    end
  end

  # Makes the constant `id` of `klass` visible. A hidden file set it in a
  # module that the program can reach, as eval support's digest/sha2 sets
  # Digest::SHA256, and now the program required that file itself.
  #: (value, word) -> void
  def zr_const_reveal_in(klass, id)
    e = zr_const_row_kept(klass, id)
    if e != 0 && CEntry[e].concealed != 0
      CEntry[e].concealed = 0
      zr_consts_changed()
    end
  end

  # Returns the constant entry that a `class` or `module` body opens. A
  # hidden entry becomes visible, so a program that reopens a module of the
  # runtime adds to the same module that the runtime uses. When a hidden
  # file reopens it, the runtime records that file as one that defined it.
  #: (value, word) -> ptr
  def zr_const_row_opened(scope, id)
    e = zr_const_row_kept(scope, id)
    if e != 0 && CEntry[e].concealed != 0
      if zr_hidden_now()
        zr_hidden_defined_in(scope, id)
      else
        CEntry[e].concealed = 0
        zr_consts_changed()
      end
    end
    e
  end

  # Returns the constant entry for `id` on `klass` alone, hidden or not, or 0.
  #: (value, word) -> ptr
  def zr_const_row_kept(klass, id)
    ext = RClass[klass].ext
    n = ClassExt[ext].clen
    if n >= CONST_INDEX_MIN
      i = zr_const_index_find(ext, id)
      if i < 0
        return 0
      end
      return zr_box_const_hidden(klass, i) ? 0 : ClassExt[ext].ctab + (i * CEntry.size)
    end
    i = 0
    while i < n
      e = ClassExt[ext].ctab + (i * CEntry.size)
      if CEntry[e].id == id
        return zr_box_const_hidden(klass, i) ? 0 : e
      end
      i += 1
    end
    0
  end

  # vm_ensure_not_refinement_module: a constant or a class variable that
  # code whose self is a refinement writes goes to the class or module
  # around the refine block, with a warning.
  #: () -> void
  def zr_refinement_self_warn
    s = Frame[Task[zr_task()].top].self
    if !zr_special_p(s) && zr_type(s) == T_MODULE && ClassExt[RClass[s].ext].refined != QNIL
      zr_warn_here(Machine.bytes("not defined at the refinement, but at the outer class/module"), 60)
    end
  end

  # Stores a constant under `klass`, then calls the `const_added` hook. An
  # anonymous class or module gets the name of the constant. Returns `v`,
  # or undef when the store or the hook raises.
  #: (value, word, value) -> value
  def zr_const_set(klass, id, v)
    if zr_const_write(klass, id, v) == 0
      return Machine.value(QUNDEF)
    end
    r = zr_const_announce(klass, id)
    return r if r == QUNDEF
    v
  end

  # Calls the `const_added` hook for `id` on `klass` when the program
  # defined one and a frame of the program set the constant. Returns the
  # value of the hook, or undef when it raises, or nil when there is no hook.
  #: (value, word) -> value
  def zr_const_announce(klass, id)
    if zr_frame_with_file(Task[zr_task()].top) != 0 && zr_find_method(zr_class_of(klass), Machine.id(:const_added)) != 0
      return zr_hook(klass, Machine.id(:const_added), zr_sym(id))
    end
    Machine.value(QNIL)
  end

  # Returns the constant entry of `klass` that contains `v` under `id`. It
  # makes a new entry or uses the old one, and records the source position.
  # Returns 0 when the store raises.
  #: (value, word, value) -> ptr
  def zr_const_write(klass, id, v)
    # `1::WHAT = 2` comes here with a scope that has no constants.
    if zr_special_p(klass) || (zr_type(klass) != T_CLASS && zr_type(klass) != T_MODULE)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      shown = zr_inspect(klass)
      if shown == QUNDEF
        return 0
      end
      zr_buf_str(b, shown)
      zr_buf_push(b, Machine.bytes(" is not a class/module"), 22)
      zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      return 0
    end
    if zr_class_modify_check(klass) == QUNDEF
      return 0
    end
    e = zr_const_row_kept(klass, id)
    if e != 0 && CEntry[e].concealed != 0 && !zr_const_sees_concealed()
      # When the program sets a constant with a name that the runtime hides,
      # the program's constant takes the entry as a new one: public, and
      # not deprecated.
      CEntry[e].concealed = 0
      CEntry[e].private = 0
      CEntry[e].deprecated = 0
      CEntry[e].value = Machine.value(QUNDEF)
    end
    if e == 0
      ext = RClass[klass].ext
      n = ClassExt[ext].clen
      if n == ClassExt[ext].ccap
        cap = n * 2
        if cap < 8
          cap = 8
        end
        tab = zr_xmalloc(cap * CEntry.size)
        if ClassExt[ext].ctab != 0
          zr_memcpy(tab, ClassExt[ext].ctab, n * CEntry.size)
          zr_xfree(ClassExt[ext].ctab)
        end
        ClassExt[ext].ctab = tab
        ClassExt[ext].ccap = cap
      end
      e = ClassExt[ext].ctab + (n * CEntry.size)
      CEntry[e].id = id
      CEntry[e].private = 0
      CEntry[e].deprecated = 0
      CEntry[e].owner = klass
      CEntry[e].concealed = 0
      if zr_hidden_now()
        CEntry[e].concealed = 1
        zr_hidden_defined_in(klass, id)
      end
      ClassExt[ext].clen = n + 1
      zr_const_index_add(ext, n)
    elsif CEntry[e].value != QUNDEF
      zr_warn_reassigned_constant(klass, id, e)
    elsif v != QUNDEF
      # A value set on a name that still waits for its autoload file stays,
      # and the autoload stops waiting for the file.
      zr_autoload_forget(klass, id)
    end
    CEntry[e].value = v
    zr_write_barrier(klass, v)
    zr_consts_changed()
    # An anonymous class gets its name here. The name is permanent under a
    # scope with a permanent name (and then the classes it contains get
    # permanent names too). Otherwise the name is temporary.
    # Under an anonymous scope, only a class with no name gets one: a
    # temporary name stays as it is.
    if !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) && (RClass[v].name == QNIL || (RBasic[v].flags & FL_TEMP_NAME) != 0)
      if zr_class_named_for_good(klass)
        RClass[v].name = zr_class_name_under(klass, id)
        RBasic[v].flags = RBasic[v].flags & (0 - (FL_TEMP_NAME + 1))
        zr_name_nested(v)
      elsif RClass[v].name == QNIL
        RClass[v].name = zr_class_name_under(klass, id)
        RBasic[v].flags = RBasic[v].flags | FL_TEMP_NAME
      end
    end
    top = zr_frame_with_file(Task[zr_task()].top)
    if top == 0
      CEntry[e].file = 0
      CEntry[e].file_len = 0
      CEntry[e].line = 0
    else
      CEntry[e].file = FrameMeta[Frame[top].meta].file
      CEntry[e].file_len = FrameMeta[Frame[top].meta].file_len
      CEntry[e].line = zr_frame_line(top)
    end
    e
  end

  # Warns `already initialized constant M::X`, and gives the location of
  # the first definition when the file is known, each through Warning.warn.
  # It warns nothing while the runtime boots.
  #: (value, word, ptr) -> void
  def zr_warn_reassigned_constant(klass, id, e)
    if Task[zr_task()].top == 0 || zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("already initialized constant "), 29)
    if klass != zr_global(G_OBJECT)
      zr_buf_str(b, zr_class_to_s(klass, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
      zr_buf_push(b, Machine.bytes("::"), 2)
    end
    zr_buf_sym(b, id)
    zr_warn_here(Buf[b].ptr, Buf[b].len)
    if CEntry[e].file_len > 0
      Buf[b].len = 0
      zr_buf_push(b, CEntry[e].file, CEntry[e].file_len)
      zr_buf_byte(b, 58)
      zr_buf_long(b, CEntry[e].line)
      zr_buf_push(b, Machine.bytes(": warning: previous definition of "), 34)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" was here\n"), 10)
      # rb_compile_warn: through Warning.warn, as the first line.
      zr_warning_write(zr_buf_take(b))
    else
      zr_buf_free(b)
    end
  end

  # Appends `\nfile:line: previous definition of Name was here` to a
  # message about a constant. A constant that the runtime set has no file
  # and no line, and CRuby prints them empty.
  #: (ptr, ptr, word) -> void
  def zr_buf_previous_definition(b, e, id)
    zr_buf_byte(b, 10)
    zr_buf_push(b, CEntry[e].file, CEntry[e].file_len)
    zr_buf_byte(b, 58)
    if CEntry[e].file_len > 0
      zr_buf_long(b, CEntry[e].line)
    end
    zr_buf_push(b, Machine.bytes(": previous definition of "), 25)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" was here"), 9)
  end

  # The class or module whose constants the ancestor list node `node`
  # holds, or nil. A class with a prepended module keeps its constants,
  # but answers at its origin, after the module, as rb_const_search_from
  # reads it (Bug #17887). Its own node then holds none, unless the
  # lookup starts there (`first`).
  #: (value, bool) -> value
  def zr_const_holder(node, first)
    if !first && RClass[node].origin != QNIL && RClass[node].origin != node
      return Machine.value(QNIL)
    end
    if zr_type(node) == T_ICLASS
      a = RClass[node].attached
      o = zr_origin(a)
      if o != a && RClass[o].ext == RClass[node].ext
        return a
      end
    end
    node
  end

  # Returns the constant entry for `id` on `klass` or an ancestor, or 0.
  # `skip_object` leaves out Object's own constants, as `A::X` does.
  #: (value, word, bool) -> ptr
  def zr_const_row_in(klass, id, skip_object)
    first = true
    while klass != QNIL
      holder = zr_const_holder(klass, first)
      first = false
      unless holder == QNIL || (skip_object && holder == zr_global(G_OBJECT))
        e = zr_const_row(holder, id)
        if e != 0
          return e
        end
      end
      klass = RClass[klass].superclass
    end
    0
  end

  # The same lookup as a constant read. It skips a name that an autoload
  # declared but that no file will define, and continues to the next
  # ancestor. rb_const_search_from does this with its `am` guard: it runs
  # the autoload once, finds the entry still undefined, and continues to
  # the next ancestor. `rb_const_defined_0` does not: it stops at that
  # entry and returns false. Thus a read and `const_defined?` differ here.
  #: (value, word, bool) -> ptr
  def zr_const_row_read_in(klass, id, skip_object)
    first = true
    while klass != QNIL
      holder = zr_const_holder(klass, first)
      first = false
      unless holder == QNIL || (skip_object && holder == zr_global(G_OBJECT))
        e = zr_const_row(holder, id)
        if e != 0 && !zr_const_declared_only(e)
          return e
        end
      end
      klass = RClass[klass].superclass
    end
    0
  end

  # Whether `home` answers const_missing with a method that the program
  # defined. Only such a method gets its own frame. The const_missing of
  # Module raises where the lookup fails, as ruby's does.
  #: (value) -> bool
  def zr_own_const_missing_p(home)
    entry = zr_find_method(zr_class_of(home), Machine.id(:const_missing))
    entry != 0 && entry != zr_find_method_at(zr_global(G_MODULE), Machine.id(:const_missing))
  end

  #: (value, word) -> value
  def zr_send_const_missing(home, id)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_sym(id)))
    zr_send(home, Machine.id(:const_missing), 1, slot)
  end

  # A private constant read as `scope::Name`: the scope's own const_missing
  # answers, else the NameError names the class that holds the constant,
  # as rb_const_get_0 and rb_mod_const_missing do.
  #: (value, ptr, word) -> value
  def zr_private_constant_read(scope, e, id)
    return zr_send_const_missing(scope, id) if zr_own_const_missing_p(scope)
    zr_private_constant(CEntry[e].owner, id)
  end

  # Whether `v`'s method `id` is one that the program defined.
  #: (value, word) -> bool
  def zr_program_method_p(v, id)
    e = zr_find_method(zr_class_of(v), id)
    e != 0 && MEntry[e].core == 0
  end

  #: (value, word) -> value
  def zr_uninitialized_constant(scope, id)
    home = scope == QNIL ? zr_global(G_OBJECT) : scope
    return zr_send_const_missing(home, id) if zr_own_const_missing_p(home)
    traced = zr_trace_c_popped(home, Machine.id(:const_missing))
    return traced if traced == QUNDEF
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("uninitialized constant "), 23)
    if scope != QNIL && scope != zr_global(G_OBJECT) && zr_class_of(scope) != zr_global(G_BOX)
      # A program's own `name` or `inspect` names the scope, as ruby's
      # name_err_mesg_receiver_name calls them.
      if zr_program_method_p(scope, Machine.id(:name)) || zr_program_method_p(scope, Machine.id(:inspect))
        slot = Machine.slot(8)
        Machine.store64(slot, 0, Machine.word(scope))
        shown = zr_send(zr_global(G_MODULE), Machine.id(:const_scope_shown), 1, slot)
        return shown if shown == QUNDEF
        zr_buf_str(b, shown)
      else
        zr_buf_class(b, scope)
      end
      zr_buf_push(b, Machine.bytes("::"), 2)
    end
    zr_buf_sym(b, id)
    msg = zr_buf_take_at(b, ENC_USASCII)
    # rb_sprintf: a name in an encoding other than UTF-8 gives the message
    # its encoding.
    enc = zr_symbol_encoding_index(id)
    if enc != ENC_UTF8 && enc != ENC_USASCII
      zr_str_set_index(msg, enc)
    end
    e = zr_exc_new(zr_global(G_NAME_ERROR), msg)
    zr_exc_detail(e, Machine.id(:name), zr_sym(id))
    zr_exc_detail(e, Machine.id(:receiver), scope == QNIL ? zr_global(G_OBJECT) : scope)
    traced = zr_trace_missing_raise(e)
    return traced if traced == QUNDEF
    zr_raise(e)
  end

  # Reads a bare constant under `cref`, or raises `uninitialized constant`.
  #: (value, word) -> value
  def zr_const_get(cref, id)
    cref = zr_cref_lexical(cref)
    gone = Machine.slot(16)
    while true
      e = zr_const_row_under(cref, id)
      if e == 0
        return zr_uninitialized_constant(zr_cref_lookup_class(cref), id)
      end
      r = zr_const_deprecated(e, id)
      return r if r == QUNDEF
      waited = CEntry[e].value == QUNDEF
      v = zr_const_searched(e, gone)
      # After an autoload, rb_const_search reads the name again, so a
      # private or deprecated constant that the file defined is checked.
      if Machine.load64(gone, 0) == 0 && (v == QUNDEF || !waited)
        return v
      end
    end
    Machine.value(QNIL)
  end

  # Returns the constant entry for a bare constant under `cref`, or 0. The
  # search order is: the lexical scopes (the cref of an eval is not one),
  # then the ancestors of the innermost scope, then the box's own toplevel
  # and its own Object, then Object when that scope is a module.
  #: (value, word) -> ptr
  def zr_const_row_under(cref, id)
    cref = zr_cref_lexical(cref)
    c = cref
    while RCref[c].next != QNIL
      if RCref[c].eval == 0
        e = zr_const_row(zr_cref_lookup_class(c), id)
        if e != 0 && !zr_const_declared_only(e)
          return e
        end
      end
      c = RCref[c].next
    end
    e = zr_const_row_read_in(zr_cref_lookup_class(cref), id, false)
    if e == 0
      b = zr_box_current()
      if b != QNIL
        e = zr_const_row(b, id)
        object = zr_box_view(zr_global(G_OBJECT))
        if e == 0 && object != zr_global(G_OBJECT)
          e = zr_const_row(object, id)
        end
      end
    end
    if e == 0 && zr_type(zr_cref_lookup_class(cref)) == T_MODULE
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    e
  end

  # Reads a bare constant under `cref` for `||=`. Returns the value, or
  # undef without a raise.
  #: (value, word) -> value
  def zr_const_lookup(cref, id)
    e = zr_const_row_under(cref, id)
    if e == 0
      return Machine.value(QUNDEF)
    end
    zr_const_value(e)
  end

  #: (value, word) -> value
  def zr_const_lookup_at(scope, id)
    if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
      return Machine.value(QUNDEF)
    end
    e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
    if e == 0 || CEntry[e].private != 0
      return Machine.value(QUNDEF)
    end
    zr_const_value(e)
  end

  # Whether entry `e` is a name that an autoload declared and that no file
  # defined. An autoload that still waits for its file also contains
  # QUNDEF, and that one counts as defined. Thus the autoload table
  # decides: if an autoload record refers to this entry and still waits,
  # a file is still to come.
  #: (ptr) -> bool
  def zr_const_declared_only(e)
    if CEntry[e].value != QUNDEF
      return false
    end
    # Another task reads the file now, and the name waits for it.
    if zr_autoload_busy(CEntry[e].owner, CEntry[e].id)
      return false
    end
    rows = zr_autoload_rows(CEntry[e].owner)
    if zr_special_p(rows)
      return true
    end
    i = 0
    while i < RArray[rows].len
      if zr_autoload_waiting(rows, i) && zr_const_row(zr_ary_at(rows, i), zr_sym2id(zr_ary_at(rows, i + 1))) == e
        return false
      end
      i += AUTOLOAD_ROW
    end
    true
  end

  # `defined?` of a constant: true when an entry exists (an autoload entry
  # too), without a load. A name that an autoload declared and that no file
  # will define is not defined. It is in `constants` and hides a name
  # farther out, and `defined?` returns nil for it, as ruby's does.
  #: (value, word) -> value
  def zr_const_defined(cref, id)
    zr_bool(zr_const_row_under(cref, id) != 0)
  end

  #: (value, word) -> value
  def zr_const_defined_at(scope, id)
    if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
      return Machine.value(QFALSE)
    end
    e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
    zr_bool(e != 0 && CEntry[e].private == 0 && !zr_const_declared_only(e))
  end

  # Raises `private constant Foo::BAR referenced`.
  #: (value, word) -> value
  def zr_private_constant(scope, id)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("private constant "), 17)
    zr_buf_str(b, zr_class_to_s(scope, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
    zr_buf_push(b, Machine.bytes("::"), 2)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" referenced"), 11)
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
    zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
    zr_exc_detail(exc, Machine.id(:receiver), scope)
    zr_exc_raise(exc)
  end

  # Sends the warning for a deprecated constant to `Warning`, so that a
  # program can catch it or make it silent.
  #: (ptr, word) -> value
  def zr_const_deprecated(e, id)
    if CEntry[e].deprecated == 0
      return Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("constant "), 9)
    owner = CEntry[e].owner
    if owner != zr_global(G_OBJECT)
      zr_buf_str(b, zr_class_to_s(owner, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
      zr_buf_push(b, Machine.bytes("::"), 2)
    end
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" is deprecated"), 14)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_buf_take(b)))
    zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:deprecated), 1, slot)
  end

  # `private_constant(*names)`, `public_constant(*names)` and
  # `deprecate_constant(*names)` set a flag on the module's own entries.
  # A constant that the runtime's own code (the core and zr's ports, whose
  # frames name no file) makes private is a helper of the runtime that
  # ruby does not have, so the program cannot see it. An upstream library
  # that eval support also carries, such as json's
  # `private_constant :ParserOptions`, keeps the constant as ruby does.
  #: (value, word, ptr, word) -> value
  def zr_mod_constant_visibility(recv, argc, argv, private)
    # rb_mod_private_constant and the others: no name is a warning under
    # $VERBOSE true, and nothing else.
    if argc == 0
      zr_warn_no_argument(private == 1 ? Machine.id(:private_constant) : (private == 0 ? Machine.id(:public_constant) : Machine.id(:deprecate_constant)))
      return recv
    end
    asking = zr_asking_frame()
    core = asking == 0 || FrameMeta[Frame[asking].meta].file_len == 0
    i = 0
    while i < argc
      slot = Machine.slot(8)
      r = zr_const_name_id(recv, Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
      return r if r == QUNDEF
      id = Machine.load64(slot, 0)
      e = zr_const_row(recv, id)
      if e == 0
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("constant "), 9)
        zr_buf_str(b, zr_class_to_s(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
        zr_buf_push(b, Machine.bytes("::"), 2)
        zr_buf_sym(b, id)
        zr_buf_push(b, Machine.bytes(" not defined"), 12)
        exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
        zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
        zr_exc_detail(exc, Machine.id(:receiver), recv)
        return zr_exc_raise(exc)
      end
      if private < 0
        CEntry[e].deprecated = 1
      else
        CEntry[e].private = private
        if private == 1 && core
          CEntry[e].concealed = 1
        end
      end
      zr_consts_changed()
      i += 1
    end
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_private_constant(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    zr_mod_constant_visibility(recv, argc, argv, 1)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public_constant(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    zr_mod_constant_visibility(recv, argc, argv, 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_deprecate_constant(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    zr_mod_constant_visibility(recv, argc, argv, 0 - 1)
  end

  # A visibility call with no name does nothing, and under $VERBOSE true
  # it says so (rb_warning).
  #: (word) -> void
  def zr_warn_no_argument(mid)
    if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_sym(b, mid)
    zr_buf_push(b, Machine.bytes(" with no argument is just ignored"), 33)
    zr_warn_here(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
  end

  # Raises TypeError unless `scope` is a class or a module, as the scope of
  # a constant path must be (`12::Name`, `class nil::Name`). Returns QUNDEF
  # after the raise, else nil.
  #: (value) -> value
  def zr_namespace_check(scope)
    if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      s = zr_inspect(scope)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_push(b, Machine.bytes(" is not a class/module"), 22)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    Machine.value(QNIL)
  end

  # Reads `scope::Name`.
  #: (value, word) -> value
  def zr_const_get_at(scope, id)
    checked = zr_namespace_check(scope)
    return checked if checked == QUNDEF
    gone = Machine.slot(16)
    while true
      e = zr_const_row_read_in(scope, id, scope != zr_global(G_OBJECT))
      if e == 0 && zr_class_of(scope) == zr_global(G_BOX)
        # `box::Name`: the box's own constant, else the runtime's constant.
        e = zr_const_row_read_in(zr_global(G_OBJECT), id, false)
      end
      if e == 0
        return zr_uninitialized_constant(scope, id)
      end
      if CEntry[e].private != 0
        return zr_private_constant_read(scope, e, id)
      end
      r = zr_const_deprecated(e, id)
      return r if r == QUNDEF
      waited = CEntry[e].value == QUNDEF
      v = zr_const_searched(e, gone)
      # After an autoload, the name is read again, as in zr_const_get.
      if Machine.load64(gone, 0) == 0 && (v == QUNDEF || !waited)
        return v
      end
    end
    Machine.value(QNIL)
  end

  # Returns the name that a class gets under `scope`: `Outer::Name`, but
  # only `Name` when the scope is a toplevel (Object, or a box), and
  # `#<Module:0x...>::Name` under an anonymous scope.
  #: (value, word) -> value
  def zr_class_name_under(scope, id)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    index = ENC_USASCII
    ascii = true
    unless zr_toplevel_scope_p(scope)
      head = zr_class_path(scope)
      index = zr_str_encoding_index(head)
      ascii = zr_str_ascii_bytes_p(head)
      zr_buf_str(b, head)
      zr_buf_push(b, Machine.bytes("::"), 2)
    end
    tail_ascii = zr_bytes_ascii_only_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
    index = zr_enc_append(index, ascii, Buf[b].len, tail_ascii ? ENC_USASCII : zr_symbol_encoding_index(id), tail_ascii)
    zr_buf_sym(b, id)
    zr_class_name_str(zr_str_set_index(zr_buf_take(b), index))
  end

  # Returns the name of a class as rb_class_path keeps it. The name is
  # frozen, so `Module#name` returns the class's own String.
  #: (value) -> value
  def zr_class_name_str(s)
    RBasic[s].flags = RBasic[s].flags | FL_FREEZE
    s
  end

  # Whether a name made under `scope` is permanent. It is permanent under a
  # toplevel, and under a scope that has a permanent name.
  #: (value) -> bool
  def zr_class_named_for_good(scope)
    zr_toplevel_scope_p(scope) || (RClass[scope].name != QNIL && (RBasic[scope].flags & FL_TEMP_NAME) == 0)
  end

  # `mod` just got a permanent name. Each class or module that it contains
  # and that has a temporary name gets its path under `mod`, recursively,
  # as CRuby's set_namespace_path does.
  #: (value) -> void
  def zr_name_nested(mod)
    ext = RClass[mod].ext
    i = 0
    while i < ClassExt[ext].clen
      v = CEntry[ClassExt[ext].ctab + (i * CEntry.size)].value
      if v != QUNDEF && !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) && (RBasic[v].flags & FL_TEMP_NAME) != 0
        RBasic[v].flags = RBasic[v].flags & (0 - (FL_TEMP_NAME + 1))
        RClass[v].name = zr_class_name_under(mod, CEntry[ClassExt[ext].ctab + (i * CEntry.size)].id)
        zr_name_nested(v)
      end
      i += 1
    end
  end

  # `mod` just got the temporary name `name`, or lost it (nil). Each class
  # or module that it contains with no permanent name takes its path under
  # the new name, or none, recursively, as set_sub_temporary_name does. A
  # module on the path that is being renamed keeps its name, so a constant
  # that refers back up the path ends the walk.
  #: (value, value) -> void
  def zr_rename_nested(mod, name)
    mid = Machine.id(:set_temporary_name)
    if zr_guard_enter(mod, mid)
      return
    end
    zr_rename_children(mod, mid)
    zr_guard_leave(mod, mid)
  end

  #: (value, word) -> void
  def zr_rename_children(mod, mid)
    ext = RClass[mod].ext
    i = 0
    while i < ClassExt[ext].clen
      e = ClassExt[ext].ctab + (i * CEntry.size)
      v = CEntry[e].value
      if v != QUNDEF && !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) &&
         (RClass[v].name == QNIL || (RBasic[v].flags & FL_TEMP_NAME) != 0) && !zr_guard_enter(v, mid)
        if RClass[mod].name == QNIL
          RClass[v].name = Machine.value(QNIL)
          RBasic[v].flags = RBasic[v].flags & (0 - (FL_TEMP_NAME + 1))
        else
          RClass[v].name = zr_class_name_under(mod, CEntry[e].id)
          RBasic[v].flags = RBasic[v].flags | FL_TEMP_NAME
        end
        zr_rename_children(v, mid)
        zr_guard_leave(v, mid)
      end
      i += 1
    end
  end

  # `class Name < sup` under `scope`. Returns the class of the constant when
  # it exists (and its superclass agrees), else a new class. `sup` is undef
  # when the program gave no superclass. `scoped` is 1 for a path with a
  # scope (`class A::Name`, `class ::Name`), which cannot reopen a private
  # constant.
  # A toplevel `class Name` looks at Object's own entries alone, as
  # rb_const_defined_at does: a Kernel::Name is not reopened.
  #: (value, word, value, word) -> value
  def zr_class_define(scope, id, sup, scoped)
    checked = zr_namespace_check(scope)
    return checked if checked == QUNDEF
    e = zr_const_row_opened(scope, id)
    if e == 0 && zr_box_current() != QNIL
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    if e != 0 && CEntry[e].value == QUNDEF && zr_autoload_pending(scope, id) < 0
      e = 0
    end
    k = Machine.value(QUNDEF)
    # vm_const_get_under: a scoped path reads the constant as a public one.
    if e != 0 && scoped != 0 && CEntry[e].private != 0
      return zr_private_constant_read(scope, e, id)
    end
    if e != 0
      # If the autoload file leaves the name undefined, or is the file that
      # loads now, this definition defines the name.
      gone = Machine.slot(16)
      k = zr_const_searched(e, gone)
      return k if k == QUNDEF
      if Machine.load64(gone, 0) != 0
        e = 0
      end
    end
    if e != 0
      if zr_special_p(k) || zr_type(k) != T_CLASS
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_sym(b, id)
        zr_buf_push(b, Machine.bytes(" is not a class"), 15)
        zr_buf_previous_definition(b, e, id)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      if sup != QUNDEF && zr_real_superclass(k) != sup
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("superclass mismatch for class "), 30)
        zr_buf_sym(b, id)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      return k
    end
    if sup == QUNDEF
      sup = zr_global(G_OBJECT)
    else
      r = zr_check_inheritable(sup)
      return r if r == QUNDEF
    end
    k = zr_class_new(sup)
    r = zr_const_set(scope, id, k)
    return r if r == QUNDEF
    r = zr_hook(sup, Machine.id(:inherited), k)
    return r if r == QUNDEF
    k
  end

  #: (value, word, word) -> value
  def zr_module_define(scope, id, scoped)
    checked = zr_namespace_check(scope)
    return checked if checked == QUNDEF
    e = zr_const_row_opened(scope, id)
    if e == 0 && zr_box_current() != QNIL
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    if e != 0 && CEntry[e].value == QUNDEF && zr_autoload_pending(scope, id) < 0
      e = 0
    end
    m = Machine.value(QUNDEF)
    # vm_const_get_under: a scoped path reads the constant as a public one.
    if e != 0 && scoped != 0 && CEntry[e].private != 0
      return zr_private_constant_read(scope, e, id)
    end
    if e != 0
      # If the autoload file leaves the name undefined, or is the file that
      # loads now, this definition defines the name.
      gone = Machine.slot(16)
      m = zr_const_searched(e, gone)
      return m if m == QUNDEF
      if Machine.load64(gone, 0) != 0
        e = 0
      end
    end
    if e != 0
      if zr_special_p(m) || zr_type(m) != T_MODULE
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_sym(b, id)
        zr_buf_push(b, Machine.bytes(" is not a module"), 16)
        zr_buf_previous_definition(b, e, id)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      return m
    end
    m = zr_module_new()
    zr_const_set(scope, id, m)
  end

  # rb_define_module_under, for a module name that an extension gives but
  # that is not a valid constant name (IO::generic_readable).
  #: (value, value) -> value
  def zr_module_define_m(scope, name)
    zr_module_define(scope, zr_sym2id(name), 0)
  end

  # The `class` keyword for the tree-walking interpreter: the same steps
  # as compiled code, so the class has its name before the superclass's
  # `inherited` runs. `given` is false when the program gave no
  # superclass, and `scoped` is true for a path with a scope.
  #: (value, value, value, value, value) -> value
  def zr_class_define_m(scope, name, sup, given, scoped)
    zr_class_define(scope, zr_sym2id(name), given == QTRUE ? sup : Machine.value(QUNDEF), scoped == QTRUE ? 1 : 0)
  end

  # The `module` keyword for the tree-walking interpreter.
  #: (value, value, value) -> value
  def zr_module_define_scoped_m(scope, name, scoped)
    zr_module_define(scope, zr_sym2id(name), scoped == QTRUE ? 1 : 0)
  end

  # Writes the id of a constant name, given as a Symbol or String, to
  # `out`. Otherwise raises `wrong constant name x`. A valid name is an
  # upper-case letter, then letters, digits, underscores or non-ASCII bytes.
  #: (value, value, ptr) -> value
  def zr_const_name_id(recv, name, out)
    r = zr_name_id(name, out)
    return r if r == QUNDEF
    id = Machine.load64(out, 0)
    unless zr_const_name_p(id)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong constant name "), 20)
      zr_buf_sym(b, id)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), name)
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_exc_raise(exc)
    end
    Machine.value(QNIL)
  end

  # Whether the symbol `id` names a constant: a capital letter first, then
  # letters, digits and `_`. A name with a byte past ASCII is read by
  # character, in its own encoding.
  #: (word) -> bool
  def zr_const_name_p(id)
    p = zr_symbol_name_ptr(id)
    n = zr_symbol_name_len(id)
    if n == 0
      return false
    end
    i = 0
    while i < n
      if Machine.u8(Machine.load8(p + i, 0)) >= 128
        return zr_const_wide_name_p(id)
      end
      i += 1
    end
    c = Machine.u8(Machine.load8(p, 0))
    if c < 65 || c > 90
      return false
    end
    i = 1
    while i < n
      c = Machine.u8(Machine.load8(p + i, 0))
      alpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
      unless alpha || (c >= 48 && c <= 57) || c == 95
        return false
      end
      i += 1
    end
    true
  end

  # Whether a name with a character past ASCII names a constant, as
  # rb_enc_symname_type reads it. The core's Unicode tables answer.
  #: (word) -> bool
  def zr_const_wide_name_p(id)
    name = zr_str_new(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
    zr_str_set_index(name, zr_symbol_encoding_index(id))
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(name))
    zr_send(zr_global(G_MODULE), Machine.id(:const_name?), 1, slot) == QTRUE
  end

  # Returns the constant entry for one segment of a `const_get` path. The
  # first segment uses the `const_get` lookup. A later segment leaves out
  # Object's constants.
  #: (value, word, value, value) -> ptr
  def zr_const_row_segment(recv, id, inherit, later)
    depth = Machine.static(:const_reflective, 8)
    Machine.store64(depth, 0, Machine.load64(depth, 0) + 1)
    e = if inherit == QFALSE || inherit == QNIL
          zr_const_row(recv, id)
        elsif later == QTRUE
          zr_const_row_read_in(recv, id, recv != zr_global(G_OBJECT))
        else
          zr_const_row_for(recv, id, true)
        end
    Machine.store64(depth, 0, Machine.load64(depth, 0) - 1)
    e
  end

  #: (value, value, value, value) -> value
  def zr_mod_const_get_m(recv, name, inherit, later)
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, name, slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    e = zr_const_row_segment(recv, id, inherit, later)
    if e == 0
      return zr_uninitialized_constant(recv, id)
    end
    # rb_const_get warns for a deprecated constant, a private one too.
    r = zr_const_deprecated(e, id)
    return r if r == QUNDEF
    e = zr_const_row_segment(recv, id, inherit, later)
    if e == 0
      return zr_uninitialized_constant(recv, id)
    end
    zr_const_value(e)
  end

  # Returns `[file, line]` of the entry, `[]` for an entry that the runtime
  # made, or nil when there is no entry.
  #: (value, value, value, value) -> value
  def zr_mod_const_source_location_m(recv, name, inherit, later)
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, name, slot)
    return r if r == QUNDEF
    e = zr_const_row_segment(recv, Machine.load64(slot, 0), inherit, later)
    # A name whose autoload file this task reads now is not defined for
    # it yet, but its place is still where `autoload` declared it.
    if e == 0
      e = zr_const_row(recv, Machine.load64(slot, 0))
    end
    if e == 0
      return Machine.value(QNIL)
    end
    # While another task reads the autoload file, the constant that the
    # file assigned is not visible here, so its place is the autoload's.
    i = zr_autoload_busy_row(CEntry[e].owner, CEntry[e].id)
    if i >= 0
      place = zr_ary_at(zr_global(G_AUTOLOADING), i + AUTOLOADING_PLACE)
      return zr_ary_subseq(place, 0, RArray[place].len)
    end
    zr_const_place(e)
  end

  # `[file, line]` of entry `e`, or `[]` when it has no file.
  #: (ptr) -> value
  def zr_const_place(e)
    out = zr_ary_new(2)
    if CEntry[e].file_len > 0
      zr_ary_push(out, zr_str_new(CEntry[e].file, CEntry[e].file_len))
      zr_ary_push(out, zr_fix(CEntry[e].line))
    end
    out
  end

  #: (value, value, value, value) -> value
  def zr_mod_const_defined_m(recv, name, inherit, later)
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, name, slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    # `rb_const_defined_0` stops at an entry that an autoload declared and
    # that no file will define. It returns false there and does not continue,
    # so the name hides a name of its own farther out.
    e = zr_const_row_segment_defined(recv, id, inherit, later)
    zr_bool(e != 0 && !zr_const_declared_only(e))
  end

  # The `const_defined?` lookup, which stops at the first entry that it
  # finds, declared or not.
  #: (value, word, value, value) -> ptr
  def zr_const_row_segment_defined(recv, id, inherit, later)
    depth = Machine.static(:const_reflective, 8)
    Machine.store64(depth, 0, Machine.load64(depth, 0) + 1)
    e = if inherit == QFALSE || inherit == QNIL
          zr_const_row(recv, id)
        elsif later == QTRUE
          zr_const_row_in(recv, id, recv != zr_global(G_OBJECT))
        else
          zr_const_row_defined_for(recv, id)
        end
    Machine.store64(depth, 0, Machine.load64(depth, 0) - 1)
    e
  end

  # The two steps of `rb_const_defined_0`: the ancestor list, then Object
  # when the receiver is a module.
  #: (value, word) -> ptr
  def zr_const_row_defined_for(mod, id)
    e = zr_const_row_in(mod, id, false)
    if e == 0 && zr_type(mod) == T_MODULE
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    e
  end

  # `remove_const(name)`: removes the module's own entry and returns its value.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_remove_const(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    r = zr_class_modify_check(recv)
    return r if r == QUNDEF
    e = zr_const_row(recv, id)
    if e == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("constant "), 9)
      zr_buf_str(b, zr_class_to_s(recv, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
      zr_buf_push(b, Machine.bytes("::"), 2)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" not defined"), 12)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
      return zr_exc_raise(exc)
    end
    # rb_const_remove warns for a deprecated constant first.
    r = zr_const_deprecated(e, id)
    return r if r == QUNDEF
    # The warning can run a program's Warning.warn, which can move the
    # table.
    e = zr_const_row(recv, id)
    if e == 0
      return Machine.value(QNIL)
    end
    v = CEntry[e].value
    zr_const_remove(recv, id)
    # A name that still waits for its file also forgets the file, and
    # returns nil, as CRuby's rb_const_remove does.
    if v == QUNDEF
      zr_autoload_forget(recv, id)
      return Machine.value(QNIL)
    end
    v
  end

  # Returns the constant entry that `const_get` and `const_defined?` find:
  # the module's own, its ancestors' when `inherit` is true, and Object's
  # for a module in all cases.
  #: (value, word, bool) -> ptr
  def zr_const_row_for(mod, id, inherit)
    if inherit
      e = zr_const_row_read_in(mod, id, false)
      if e == 0 && zr_type(mod) == T_MODULE
        e = zr_const_row_read_in(zr_global(G_OBJECT), id, false)
      end
      return e
    end
    zr_const_row(mod, id)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_const_set(recv, argc, argv, cref, blk)
    if zr_modify_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    v = Machine.value(Machine.load64(argv, 8))
    if Task[zr_task()].ractor != 0 && !zr_special_p(v)
      r = zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:const_write), 1, argv + 8)
      return r if r == QUNDEF
    end
    zr_const_set(recv, Machine.load64(slot, 0), v)
  end

  # Adds each public constant name of `klass` itself to `out`, once. A
  # module that an extension defines under a name that is no constant name
  # (IO::generic_readable) is left out, as rb_local_constants_i leaves out
  # an id that is not rb_is_const_id.
  #: (value, value) -> void
  def zr_const_names_at(klass, out)
    ext = RClass[klass].ext
    i = 0
    while i < ClassExt[ext].clen
      e = ClassExt[ext].ctab + (i * CEntry.size)
      id = CEntry[e].id
      name = zr_sym(id)
      visible = CEntry[e].private == 0 && (CEntry[e].concealed == 0 || zr_const_sees_reflectively())
      if visible && zr_const_name_p(id) && zr_ary_index_of(out, name) < 0
        zr_ary_push(out, name)
      end
      i += 1
    end
  end

  # Adds the names of `mod`, then of its ancestors up to Object. The
  # search stops at Object unless it started there, as rb_mod_const_of
  # does: a class does not see the names of Object or BasicObject.
  #: (value, value, bool) -> void
  def zr_const_names_of(mod, out, inherit)
    k = mod
    while k != QNIL && (k != zr_global(G_OBJECT) || mod == zr_global(G_OBJECT))
      zr_const_names_at(k, out)
      k = inherit ? RClass[k].superclass : Machine.value(QNIL)
    end
  end

  # `Module.constants`. With no arguments, it lists the names of each
  # lexical scope, then those of the ancestors of the innermost scope, as
  # rb_mod_s_constants does. Otherwise it returns the same as
  # `Module#constants`.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_s_constants(recv, argc, argv, cref, blk)
    if argc != 0 || recv != zr_global(G_MODULE)
      return zr_mod_constants(recv, argc, argv, cref, blk)
    end
    out = zr_ary_new(8)
    c = zr_cref_lexical(Frame[Frame[Task[zr_task()].top].prev].cref)
    inner = zr_cref_klass(c)
    while c != QNIL
      if RCref[c].eval == 0
        zr_const_names_at(zr_cref_klass(c), out)
      end
      c = RCref[c].next
    end
    zr_const_names_of(inner, out, true)
    out
  end

  # `constants`: the names of the receiver, and of its ancestors unless
  # `inherit` is false.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_constants(recv, argc, argv, cref, blk)
    out = zr_ary_new(8)
    inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_const_names_of(recv, out, inherit)
    out
  end

  # Removes the entry for `id` from the own table of `klass`.
  #: (value, word) -> void
  def zr_const_remove(klass, id)
    ext = RClass[klass].ext
    n = ClassExt[ext].clen
    i = 0
    while i < n
      e = ClassExt[ext].ctab + (i * CEntry.size)
      if CEntry[e].id == id
        zr_memmove(e, e + CEntry.size, (n - i - 1) * CEntry.size)
        ClassExt[ext].clen = n - 1
        # The entries after it moved up by one.
        zr_const_index_drop(ext)
        zr_consts_changed()
        return
      end
      i += 1
    end
  end

  # Autoload: a constant entry whose value is undef until its file runs.
  # A module keeps its records in its autoload table (ClassExt
  # `autoloads`), so a module that nothing refers to goes with its
  # records. Each record has AUTOLOAD_ROW words: the module, the name, the
  # feature as the program wrote it, the function of the unit as a fixnum,
  # the require kind (zr_require's: 0, or 3 for eval support's own files),
  # the resolved path of the feature, the module whose autoload table
  # holds the record, and how many rows of G_AUTOLOAD_PROVIDED the record
  # has seen. A require of the same file records that path. A feature
  # that the program computed has no unit. Its kind is AUTOLOAD_REQUIRE,
  # and the first read of the constant calls `require` on main with it,
  # as ruby's autoload does. `Kernel#autoload` and `Kernel.autoload`
  # register on the class of the caller, as CRuby's rb_f_autoload does.
  #
  # The table is the module's own, except for a copy: rb_mod_init_copy
  # gives the copy its original's table, so a value set on the name in the
  # original, or its removal, ends the record of the copy too.
  AUTOLOAD_ROW = 8
  AUTOLOAD_REQUIRE = 4
  # The kind of a record whose feature a require would not read, because
  # the program contains it or a require already read it. The record stays, as ruby keeps its
  # own, but it stops counting: `autoload?` returns nil and
  # `const_defined?` returns false. The name is still declared, so the
  # constant is undefined here and hides a constant of the same name
  # farther out. A record gets this kind where it is registered, or where
  # `zr_autoload_provided` finds the require that provided its feature.
  AUTOLOAD_DECLARED = 5
  # The autoloads whose file a task reads now, as rows of the task (a
  # Fixnum of its address), the autoload's own record, and the place where
  # `autoload` declared the name. A read of the name from another task
  # waits until the row goes, as autoload_load_needed waits on the
  # autoload's mutex.
  G_AUTOLOADING = 68
  AUTOLOADING_ROW = AUTOLOAD_ROW + 2
  # The features (as the program wrote them) that a read of an autoload
  # has loaded. ruby shares one autoload record among all the names of a
  # feature, and the first read gives it a mutex that stays. From then on,
  # `check_autoload_required` (variable.c) counts each of these names as
  # waiting, whether or not $LOADED_FEATURES has the file. So a require of
  # the file does not make them declared only.
  G_AUTOLOAD_READ = 73
  # What each require provided, as rows of AUTOLOAD_PROVIDED_ROW words:
  # the feature as the program wrote it (or nil), the path of the file,
  # and how many features G_AUTOLOAD_READ had then. A record reads the
  # rows that it has not seen when it is asked whether it waits
  # (`zr_autoload_settle`), and gets the answer that it would have had
  # at each require.
  G_AUTOLOAD_PROVIDED = 38
  AUTOLOAD_PROVIDED_ROW = 3
  # The place in a row of G_AUTOLOADING. Until the file ends, other tasks
  # see this place, not the one where the file assigns the constant.
  AUTOLOADING_PLACE = AUTOLOAD_ROW + 1

  #: (value, word, value, ptr, value, word, value) -> value
  def zr_autoload(mod, id, feature, fn, cref, kind, path)
    # rb_autoload_str: an empty feature name is an error.
    if RString[feature].len == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty feature name"), 18)
    end
    # Kernel#autoload (from main, from Kernel, or from a method whose self
    # is not a module) declares on the class of the caller's cref, as
    # rb_f_autoload reads rb_vm_cbase. A cref that class_exec or
    # instance_eval pushed counts too, and for instance_eval the class is
    # the object's real class. Module#autoload declares on its receiver.
    if mod == zr_global(G_MAIN) || mod == zr_global(G_KERNEL) || zr_special_p(mod) || (zr_type(mod) != T_CLASS && zr_type(mod) != T_MODULE)
      mod = zr_cref_lookup_class(cref)
      while zr_singleton_p(mod) || zr_type(mod) == T_ICLASS
        mod = RClass[mod].superclass
      end
    end
    # A name that already has a value stays, as `autoload_synchronized`
    # (variable.c:2913) returns false for it. A name with no value (undefined,
    # waiting for a file, or waiting for a file that another require
    # provided) is declared again, and calls the hook again.
    row = zr_const_row(mod, id)
    if row != 0 && CEntry[row].value != QUNDEF
      return Machine.value(QNIL)
    end
    pending = zr_autoload_row(mod, id)
    rows = zr_autoload_table(mod)
    if pending >= 0
      zr_ary_splice(rows, zr_fix(pending), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
    end
    # Only a file that the runtime loads declared it, so the read that runs
    # it keeps the file hidden from the program, as the require would.
    if kind == 0 && zr_hidden_now()
      kind = 3
    end
    # A require already read this file, so a require of it now would read
    # no file. ruby keeps no record for that, and only declares the name.
    # The compiler does the same check for a feature that the runtime
    # contains, which is in no table that a program can read.
    if kind != AUTOLOAD_DECLARED && !zr_autoload_read(feature) &&
       zr_ary_has_bytes(zr_gvar_get(Machine.id(:$LOADED_FEATURES)), RString[path].ptr, RString[path].len)
      kind = AUTOLOAD_DECLARED
    end
    # The name is declared and the entry exists before the hook runs. Thus
    # a const_added hook that raises raises out of the autoload, and the
    # autoload stays registered, as ruby's does.
    if zr_const_write(mod, id, Machine.value(QUNDEF)) == 0
      return Machine.value(QUNDEF)
    end
    # The record goes in whether or not a file is still to come. ruby also
    # keeps a record for a feature that is already provided, but does not
    # count it. A second `autoload` of the same name replaces this record,
    # and a read of the name gets its feature from it.
    zr_autoload_push(rows, mod, id, feature, fn, kind, path, mod)
    r = zr_const_announce(mod, id)
    return r if r == QUNDEF
    Machine.value(QNIL)
  end

  # `autoload(name, feature)` with a feature that the program computed,
  # already a String. `name` is a Symbol or a String. `loaded` is true when
  # a require of the feature would read no file; then the name is declared
  # and the record does not wait. `file` is the path that a require of the
  # feature would read, or nil when no such file exists. A later require of
  # that file stops the wait, whatever spelling of the feature it uses.
  #: (value, value, value, value, value, value) -> value
  def zr_autoload_computed(mod, name, feature, cref, loaded, file)
    slot = Machine.slot(8)
    r = zr_name_id(name, slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    unless zr_const_name_p(id)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("autoload must be constant name: "), 32)
      zr_buf_sym(b, id)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take_at(b, ENC_USASCII))
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      return zr_exc_raise(exc)
    end
    if RString[feature].len == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty feature name"), 18)
    end
    zr_autoload(mod, id, feature, Machine.ptr(0), cref, loaded == QTRUE && !zr_autoload_read(feature) ? AUTOLOAD_DECLARED : AUTOLOAD_REQUIRE,
                zr_special_p(file) ? feature : file)
  end

  # A record goes in after the requires so far, which it does not see: the
  # registration checked $LOADED_FEATURES itself.
  #: (value, value, word, value, ptr, word, value, value) -> void
  def zr_autoload_push(rows, mod, id, feature, fn, kind, path, table)
    zr_ary_push(rows, mod)
    zr_ary_push(rows, zr_sym(id))
    zr_ary_push(rows, feature)
    zr_ary_push(rows, zr_fix(Machine.word(fn)))
    zr_ary_push(rows, zr_fix(kind))
    zr_ary_push(rows, path)
    zr_ary_push(rows, table)
    provided = zr_global(G_AUTOLOAD_PROVIDED)
    zr_ary_push(rows, zr_fix(zr_special_p(provided) ? 0 : RArray[provided].len))
  end

  # The autoload table of `mod`, or false if it has none.
  #: (value) -> value
  def zr_autoload_rows(mod)
    ClassExt[RClass[mod].ext].autoloads
  end

  # The autoload table of `mod`, made at its first record.
  #: (value) -> value
  def zr_autoload_table(mod)
    rows = ClassExt[RClass[mod].ext].autoloads
    if zr_special_p(rows)
      rows = zr_ary_new(AUTOLOAD_ROW)
      ClassExt[RClass[mod].ext].autoloads = rows
      zr_write_barrier(mod, rows)
    end
    rows
  end

  # A value was set on the name `id` of `mod`, or the name was removed:
  # autoload_delete removes the name from the autoload table of `mod`, so
  # each record of that table for the name goes, a copy's too.
  #: (value, word) -> void
  def zr_autoload_forget(mod, id)
    rows = zr_autoload_rows(mod)
    i = zr_autoload_row(mod, id)
    if i < 0
      table = mod
    else
      table = zr_ary_at(rows, i + 6)
    end
    i = 0
    while !zr_special_p(rows) && i < RArray[rows].len
      if zr_ary_at(rows, i + 1) == zr_sym(id) && zr_ary_at(rows, i + 6) == table
        zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
      else
        i += AUTOLOAD_ROW
      end
    end
  end

  # The first read of a constant whose feature the program computed. It
  # calls `require` on main, which a program can redefine, as ruby does.
  #: (value) -> value
  def zr_autoload_require(feature)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(feature))
    zr_send(zr_global(G_MAIN), Machine.id(:require), 1, slot)
  end

  # Whether the autoload record at `i` still waits for its file. A record
  # whose feature another require provided does not wait:
  # `check_autoload_required` (variable.c:3035) returns 0 for it, so
  # `autoload?` returns nil and `const_defined?` returns false, and ruby
  # keeps the record. Here that record has the kind AUTOLOAD_DECLARED, set
  # where it was registered or by `zr_autoload_settle`.
  #: (value, word) -> bool
  def zr_autoload_waiting(rows, i)
    zr_autoload_settle(rows, i)
    if zr_fix2long(zr_ary_at(rows, i + 4)) == AUTOLOAD_DECLARED
      return false
    end
    # The file is loading in this task, and defines the name as it runs, as
    # autoload_load_needed declines for the thread that loads the feature.
    # For another task, the record waits until that load ends.
    zr_feature_loader(zr_ary_at(rows, i + 5)) != zr_fix(Machine.word(zr_task()))
  end

  # rb_mod_init_copy: the copy of a module shares the autoload table of its
  # original, so each record of the original gets a twin for the copy in
  # the same table.
  #: (value, value) -> void
  def zr_autoload_copy(orig, copy)
    rows = zr_autoload_rows(orig)
    if zr_special_p(rows)
      return
    end
    ClassExt[RClass[copy].ext].autoloads = rows
    zr_write_barrier(copy, rows)
    n = RArray[rows].len
    i = 0
    while i < n
      if zr_ary_at(rows, i) == orig
        zr_ary_push(rows, copy)
        j = 1
        while j < AUTOLOAD_ROW
          zr_ary_push(rows, zr_ary_at(rows, i + j))
          j += 1
        end
      end
      i += AUTOLOAD_ROW
    end
  end

  # Returns the index of the autoload record for `mod` and `id` when a file
  # is still to come, or -1. Most callers use this. The three callers that
  # need the record in all cases (a second `autoload`, a value written on
  # the name, and `remove_const`) use `zr_autoload_row`.
  #: (value, word) -> word
  def zr_autoload_pending(mod, id)
    i = zr_autoload_row(mod, id)
    if i < 0 || !zr_autoload_waiting(zr_autoload_rows(mod), i)
      return 0 - 1
    end
    i
  end

  # A require read the file at `path`, which the program requested by the
  # name `feature`. Every autoload record for either string stops waiting.
  #
  # ruby calls `rb_feature_provided` on the feature of the record each time
  # it checks whether the record is pending. Here the answer is fixed at
  # the require, as if each record were checked then. The kernel cannot do
  # the check later, because the resolution of a feature to a file is the
  # work of `Kernel.feature_path` and uses $LOAD_PATH. It compares both
  # strings because a record keeps the feature as written and the file that
  # it resolved to at registration. If $LOAD_PATH grew between the two, only
  # the feature can match.
  #: (value, value) -> value
  def zr_autoload_provided(feature, path)
    provided = zr_global_list(G_AUTOLOAD_PROVIDED)
    read = zr_global(G_AUTOLOAD_READ)
    zr_ary_push(provided, feature)
    zr_ary_push(provided, path)
    zr_ary_push(provided, zr_fix(zr_special_p(read) ? 0 : RArray[read].len))
    Machine.value(QNIL)
  end

  # The record at `i` reads the requires that it has not seen. A require
  # of its feature or its path makes it AUTOLOAD_DECLARED, unless a read of
  # an autoload had loaded its feature before that require.
  #: (value, word) -> void
  def zr_autoload_settle(rows, i)
    provided = zr_global(G_AUTOLOAD_PROVIDED)
    if zr_special_p(provided)
      return
    end
    seen = zr_fix2long(zr_ary_at(rows, i + 7))
    n = RArray[provided].len
    if seen >= n
      return
    end
    kept = zr_ary_at(rows, i + 2)
    while seen < n && zr_fix2long(zr_ary_at(rows, i + 4)) != AUTOLOAD_DECLARED
      if (zr_autoload_names(kept, zr_ary_at(provided, seen)) || zr_autoload_names(zr_ary_at(rows, i + 5), zr_ary_at(provided, seen + 1))) &&
         !zr_autoload_read_in(kept, zr_fix2long(zr_ary_at(provided, seen + 2)))
        zr_ary_store(rows, i + 4, zr_fix(AUTOLOAD_DECLARED))
      end
      seen += AUTOLOAD_PROVIDED_ROW
    end
    zr_ary_store(rows, i + 7, zr_fix(n))
  end

  # Whether a read of an autoload has loaded `feature` (G_AUTOLOAD_READ).
  #: (value) -> bool
  def zr_autoload_read(feature)
    read = zr_global(G_AUTOLOAD_READ)
    if zr_special_p(read)
      return false
    end
    zr_autoload_read_in(feature, RArray[read].len)
  end

  # The same, among the first `n` features that autoloads read.
  #: (value, word) -> bool
  def zr_autoload_read_in(feature, n)
    read = zr_global(G_AUTOLOAD_READ)
    if zr_special_p(read)
      return false
    end
    i = 0
    while i < n
      if zr_autoload_names(zr_ary_at(read, i), feature)
        return true
      end
      i += 1
    end
    false
  end

  # Whether the `kept` string of the record is `asked`. A record registered
  # before its feature could be resolved has no path, and nothing matches it.
  #: (value, value) -> bool
  def zr_autoload_names(kept, asked)
    if zr_special_p(kept) || zr_special_p(asked) || zr_type(kept) != T_STRING || zr_type(asked) != T_STRING
      return false
    end
    zr_bytes_eq(RString[kept].ptr, RString[kept].len, RString[asked].ptr, RString[asked].len)
  end

  # Returns the index of the autoload record for `mod` and `id`, waiting or
  # not, or -1.
  #: (value, word) -> word
  def zr_autoload_row(mod, id)
    rows = zr_autoload_rows(mod)
    if zr_special_p(rows)
      return 0 - 1
    end
    i = 0
    while i < RArray[rows].len
      if zr_ary_at(rows, i) == mod && zr_ary_at(rows, i + 1) == zr_sym(id)
        return i
      end
      i += AUTOLOAD_ROW
    end
    0 - 1
  end

  # `autoload?(name)`: returns the feature still to load, or nil. While
  # another task reads the file, the name still waits for this one, so it
  # returns the feature; the task that reads it gets nil.
  #: (value, word) -> value
  def zr_autoload_feature(mod, id)
    i = zr_autoload_pending(mod, id)
    if i >= 0
      return zr_ary_at(zr_autoload_rows(mod), i + 2)
    end
    i = zr_autoload_busy_row(mod, id)
    if i >= 0
      return zr_ary_at(zr_global(G_AUTOLOADING), i + 3)
    end
    Machine.value(QNIL)
  end

  # Returns the value of a constant entry. An autoload's file runs first,
  # and then the constant that it defined is the value. A file that defines
  # nothing leaves the name uninitialized.
  # A box that reads a shared class gets its shadow of that class.
  #: (ptr) -> value
  def zr_const_value(e)
    zr_box_seen(zr_const_raw_value(e))
  end

  #: (ptr) -> value
  def zr_const_raw_value(e)
    gone = Machine.slot(16)
    Machine.store64(gone, 0, 0)
    v = zr_const_loaded(e, gone)
    if Machine.load64(gone, 0) != 0
      return zr_uninitialized_constant(Machine.value(Machine.load64(gone, 0)), Machine.load64(gone, 8))
    end
    v
  end

  # The same, for a search that continues past an entry that an autoload
  # removed, as CRuby's rb_const_search does. When the entry is removed,
  # `gone` contains its module, and the value is nil.
  #: (ptr, ptr) -> value
  def zr_const_searched(e, gone)
    Machine.store64(gone, 0, 0)
    v = zr_const_loaded(e, gone)
    if v == QUNDEF || Machine.load64(gone, 0) != 0
      return v
    end
    zr_box_seen(v)
  end

  # Returns the value of entry `e`, and runs an autoload's file first. A
  # file that leaves the name undefined removes the entry. So does a file
  # that is already loading, because its own `class` or `module` can be what
  # defines the name. Then `gone` contains the module and the name, and the
  # value is nil.
  #: (ptr, ptr) -> value
  def zr_const_loaded(e, gone)
    v = CEntry[e].value
    mod = CEntry[e].owner
    id = CEntry[e].id
    # While another task reads the autoload file of the name, a value that
    # the file set is that task's own: CRuby keeps it in the autoload's
    # record (autoload_const) until the file ends, so this read waits.
    if v != QUNDEF && !zr_autoload_busy(mod, id)
      return v
    end
    if zr_autoload_busy(mod, id)
      args = Machine.slot(16)
      Machine.store64(args, 0, Machine.word(Machine.value(QNIL)))
      Machine.store64(args, 8, Machine.word(Machine.value(QFALSE)))
      while zr_autoload_busy(mod, id)
        waited = zr_send(zr_global(G_KERNEL), Machine.id(:feature_busy), 2, args)
        return waited if waited == QUNDEF
      end
      e = zr_const_row(mod, id)
      if e == 0
        Machine.store64(gone, 0, Machine.word(mod))
        Machine.store64(gone, 8, id)
        return Machine.value(QNIL)
      end
      v = CEntry[e].value
      if v != QUNDEF
        return v
      end
    end
    rows = zr_autoload_rows(mod)
    i = 0
    while !zr_special_p(rows) && i < RArray[rows].len
      mod = zr_ary_at(rows, i)
      id = zr_sym2id(zr_ary_at(rows, i + 1))
      # An autoload record that does not wait reads no file: a require provided
      # its feature, so a require of it now would return false and define
      # nothing. The loop skips it, and the name stays undefined, as in ruby:
      # `rb_autoload_load` declines, and the read raises at that name.
      if zr_autoload_waiting(rows, i) && zr_const_row(mod, id) == e
        feature = zr_ary_at(rows, i + 2)
        fn = Machine.ptr(zr_fix2long(zr_ary_at(rows, i + 3)))
        kind = zr_fix2long(zr_ary_at(rows, i + 4))
        # A file that the runtime alone loaded made a hidden record (3). If
        # the program has required that file since, the name is the
        # program's to see, and so is the file that its autoload reads.
        if kind == 3 && CEntry[e].concealed == 0
          kind = 0
        end
        path = zr_ary_at(rows, i + 5)
        table = zr_ary_at(rows, i + 6)
        zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
        if !zr_autoload_read(feature)
          zr_ary_push(zr_global_list(G_AUTOLOAD_READ), feature)
        end
        busy = zr_global_list(G_AUTOLOADING)
        zr_ary_push(busy, zr_fix(Machine.word(zr_task())))
        zr_autoload_push(busy, mod, id, feature, fn, kind, path, table)
        zr_ary_push(busy, zr_const_place(e))
        r = kind == AUTOLOAD_REQUIRE ? zr_autoload_require(feature) : zr_require(path, fn, kind)
        zr_autoload_done(mod, id)
        # If the file did not load, the entry stays, so the next read of the name
        # does the same check again.
        if r == QUNDEF
          zr_autoload_push(rows, mod, id, feature, fn, kind, path, table)
          return r
        end
        e = zr_const_row(mod, id)
        if e == 0 || CEntry[e].value == QUNDEF
          zr_const_remove(mod, id)
          if r == QTRUE
            zr_warn_autoload_undefined(mod, id, feature)
          end
          Machine.store64(gone, 0, Machine.word(mod))
          Machine.store64(gone, 8, id)
          return Machine.value(QNIL)
        end
        return CEntry[e].value
      end
      i += AUTOLOAD_ROW
    end
    zr_uninitialized_constant(Machine.value(QNIL), CEntry[e].id)
  end

  # Whether a task other than this one reads the file of the autoload of
  # `mod` and `id` now.
  #: (value, word) -> bool
  def zr_autoload_busy(mod, id)
    zr_autoload_busy_row(mod, id) >= 0
  end

  # The index in G_AUTOLOADING of the row of another task that reads the
  # file of the autoload of `mod` and `id` now, or -1.
  #: (value, word) -> word
  def zr_autoload_busy_row(mod, id)
    rows = zr_global(G_AUTOLOADING)
    if zr_special_p(rows)
      return 0 - 1
    end
    task = zr_fix(Machine.word(zr_task()))
    i = 0
    while i < RArray[rows].len
      if zr_ary_at(rows, i + 1) == mod && zr_ary_at(rows, i + 2) == zr_sym(id) && zr_ary_at(rows, i) != task
        return i
      end
      i += AUTOLOADING_ROW
    end
    0 - 1
  end

  # Whether any task reads the file of the autoload of `mod` and `id` now.
  #: (value, word) -> bool
  def zr_autoload_running(mod, id)
    rows = zr_global(G_AUTOLOADING)
    if zr_special_p(rows)
      return false
    end
    i = 0
    while i < RArray[rows].len
      if zr_ary_at(rows, i + 1) == mod && zr_ary_at(rows, i + 2) == zr_sym(id)
        return true
      end
      i += AUTOLOADING_ROW
    end
    false
  end

  # This task's read of the file of the autoload of `mod` and `id` ended.
  #: (value, word) -> void
  def zr_autoload_done(mod, id)
    rows = zr_global(G_AUTOLOADING)
    task = zr_fix(Machine.word(zr_task()))
    i = 0
    while i < RArray[rows].len
      if zr_ary_at(rows, i + 1) == mod && zr_ary_at(rows, i + 2) == zr_sym(id) && zr_ary_at(rows, i) == task
        zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOADING_ROW), zr_ary_new(0))
        return
      end
      i += AUTOLOADING_ROW
    end
  end

  # In a forked child, only this task lives. A file that another task was
  # reading never ends here, so its autoload waits again, and the next read
  # of the name reads the file in the child, as CRuby takes over a lock
  # whose thread is gone. The same holds for that task's requires.
  #: () -> value
  def zr_autoload_after_fork
    task = zr_fix(Machine.word(zr_task()))
    rows = zr_global(G_AUTOLOADING)
    if !zr_special_p(rows)
      i = 0
      while i < RArray[rows].len
        if zr_ary_at(rows, i) == task
          i += AUTOLOADING_ROW
        else
          zr_autoload_push(zr_autoload_table(zr_ary_at(rows, i + 7)), zr_ary_at(rows, i + 1), zr_sym2id(zr_ary_at(rows, i + 2)), zr_ary_at(rows, i + 3),
                           Machine.ptr(zr_fix2long(zr_ary_at(rows, i + 4))), zr_fix2long(zr_ary_at(rows, i + 5)), zr_ary_at(rows, i + 6),
                           zr_ary_at(rows, i + 7))
          zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOADING_ROW), zr_ary_new(0))
        end
      end
    end
    rows = zr_global(G_LOADING_FEATURES)
    if !zr_special_p(rows)
      i = 0
      while i < RArray[rows].len
        if zr_ary_at(rows, i + 1) == task
          i += 2
        else
          # zr_require lists a file in $LOADED_FEATURES before it runs.
          zr_ary_delete_string(zr_gvar_get(Machine.id(:$LOADED_FEATURES)), zr_ary_at(rows, i))
          zr_ary_splice(rows, zr_fix(i), zr_fix(2), zr_ary_new(0))
        end
      end
    end
    Machine.value(QNIL)
  end

  # Under `$VERBOSE` true, warns that the autoload's `feature` left the
  # name undefined, as autoload_try_load does.
  #: (value, word, value) -> void
  def zr_warn_autoload_undefined(mod, id, feature)
    if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("Expected "), 9)
    zr_buf_str(b, feature)
    zr_buf_push(b, Machine.bytes(" to define "), 11)
    if mod != zr_global(G_OBJECT)
      zr_buf_str(b, zr_class_to_s(mod, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
      zr_buf_push(b, Machine.bytes("::"), 2)
    end
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" but it didn't"), 14)
    zr_warn_here(Buf[b].ptr, Buf[b].len)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_autoload_p(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    # rb_autoload_at_p: with `inherit` (the default), the first ancestor,
    # included modules too, that has an autoload of the name answers.
    inherit = argc < 2 ? Machine.value(QTRUE) : Machine.value(Machine.load64(argv, 8))
    if inherit == QNIL || inherit == QFALSE
      return zr_autoload_feature(recv, id)
    end
    k = recv
    while k != QNIL
      mod = zr_type(k) == T_ICLASS ? RClass[k].attached : k
      feature = zr_autoload_feature(mod, id)
      if feature != QNIL
        return feature
      end
      k = RClass[k].superclass
    end
    Machine.value(QNIL)
  end

  # The tree-walking interpreter (lib/zr/eval/walk.rb) reads and writes
  # constants through the kernel's own lookup, so a string that it evaluates
  # finds what compiled code finds. It has no inline cache and no symbol id,
  # so these functions take the name as a Symbol. They are in place of the
  # cached forms that the compiler emits.
  #: (value, value) -> value
  def zr_const_get_m(cref, name)
    zr_const_get(cref, zr_sym2id(name))
  end

  #: (value, value) -> value
  def zr_const_defined_m(cref, name)
    zr_const_defined(cref, zr_sym2id(name))
  end

  #: (value, value) -> value
  def zr_const_get_at_m(scope, name)
    zr_const_get_at(scope, zr_sym2id(name))
  end

  #: (value, value) -> value
  def zr_const_defined_at_m(scope, name)
    zr_const_defined_at(scope, zr_sym2id(name))
  end

  # The constant reads of the tree-walking interpreter (lib/zr/runtime/lib/
  # zr/eval/walking.rb). Its own frames are hidden, so a read would see
  # the constants that only eval support set (Zr, Prism). These read as
  # the walked program: `kind` 0 is `Name` under `at` (a cref), 1 is
  # `defined?(Name)`, 2 is `at::Name` and 3 is `defined?(at::Name)`.
  #: (word, value, value) -> value
  def zr_walk_const(kind, at, name)
    flag = Machine.static(:const_for_program, 8)
    Machine.store64(flag, 0, Machine.load64(flag, 0) + 1)
    id = zr_sym2id(name)
    r = if kind == 0
          zr_const_get(at, id)
        elsif kind == 1
          zr_const_defined(at, id)
        elsif kind == 2
          zr_const_get_at(at, id)
        else
          zr_const_defined_at(at, id)
        end
    Machine.store64(flag, 0, Machine.load64(flag, 0) - 1)
    r
  end

  #: (value, value) -> value
  def zr_walk_const_get_m(cref, name)
    zr_walk_const(0, cref, name)
  end

  #: (value, value) -> value
  def zr_walk_const_defined_m(cref, name)
    zr_walk_const(1, cref, name)
  end

  #: (value, value) -> value
  def zr_walk_const_get_at_m(scope, name)
    zr_walk_const(2, scope, name)
  end

  #: (value, value) -> value
  def zr_walk_const_defined_at_m(scope, name)
    zr_walk_const(3, scope, name)
  end

  #: (value, value, value) -> value
  def zr_const_set_m(klass, name, v)
    zr_const_set(klass, zr_sym2id(name), v)
  end
end
