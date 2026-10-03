module Zr::Kern
  # Classes and modules: a name, a superclass, and an extension outside
  # the arena. The extension contains the method table (id, code, arity,
  # kind, meta and cref entries, searched in order) and the constant table
  # (id and value entries). An included module is in the ancestor list as
  # a proxy (T_ICLASS) that shares the module's extension and refers to it
  # as `attached`. Method code takes `(recv, argc, argv, cref)` and returns
  # a Value; the cref is the lexical scope list where the method was
  # defined. `origin` is the proxy that contains a prepended class's own
  # methods, below the prepended modules, or nil.
  class RClass < Layout
    attr_reader :basic #: RBasic
    attr_accessor :name #: value
    attr_accessor :superclass #: value
    attr_accessor :ext #: ptr
    attr_accessor :attached #: value
    attr_accessor :origin #: value
  end
  # `serial` counts classes in creation order, which `subclasses` reads.
  # `refined` is the class that a refinement holder refines, and `active`
  # is the one-item activation list that only that holder makes. Both are
  # nil on a usual class or module.
  # `boxed` is the shadow class that each box sees in place of this one,
  # indexed by box slot, and `shadow` is the shared class that a shadow is
  # in place of. Both are nil outside a box.
  # `alloc` is the kind of object the class allocates (ALLOC_*), found
  # from its builtin ancestor on first use; 0 until then.
  # `saved` contains `slen` method entries: the core library's entries that
  # a program overwrote or removed. The core library's own sends still find
  # them (see zr_find_core_method).
  class ClassExt < Layout
    attr_accessor :mtab #: ptr
    attr_accessor :mlen #: word
    attr_accessor :mcap #: word
    attr_accessor :ctab #: ptr
    attr_accessor :clen #: word
    attr_accessor :ccap #: word
    attr_reader :iv #: IvTab
    attr_reader :cv #: IvTab
    attr_accessor :serial #: word
    attr_accessor :refined #: value
    attr_accessor :active #: value
    attr_accessor :boxed #: value
    attr_accessor :shadow #: value
    attr_accessor :alloc #: word
    attr_accessor :cidx #: ptr
    attr_accessor :cbins #: word
    attr_accessor :saved #: ptr
    attr_accessor :slen #: word
    attr_accessor :supers #: ptr
    attr_accessor :rank #: word
    attr_accessor :midx #: ptr
    attr_accessor :mbins #: word
    attr_accessor :obj_bytes #: word
  end
  # `orig` is the name of the first definition of the method, which an
  # alias keeps. `from` is the ancestor list node where an alias or a
  # visibility change found the entry that it copied. `super` in the body
  # continues from there, as with CRuby's alias and zsuper entries. It is
  # nil for a definition. `core` is 1 for an entry that the core library
  # wrote before the program started.
  # `ivar` is the word that a kind keeps next to its function: the inline
  # cache hint for an accessor (cache.rb), or the cref of a `define_method`
  # body, made at the first call (eval.rb, `zr_bmethod_cref`). An entry is
  # 88 bytes: a Method's cell embeds one after three Values, and a 128-byte
  # cell has no more room.
  # `direct` is the second entry point of a compiled def with only
  # required positional parameters (Zr::Lower::Function). It is the same
  # body, but takes its arguments in registers with no count to check. A
  # call site that gives exactly that many arguments calls it through its
  # cache entry (CallCache.direct). The `fn` of such a def is
  # `zr_direct_fn`, which takes the generic arguments and checks what the
  # site proved.
  class MEntry < Layout
    attr_accessor :mid #: word
    attr_accessor :fn #: ptr
    attr_accessor :arity #: word
    attr_accessor :kind #: word
    attr_accessor :meta #: ptr
    attr_accessor :cref #: value
    attr_accessor :vis #: word
    attr_accessor :orig #: word
    attr_accessor :from #: value
    attr_accessor :core #: word
    attr_reader :ivar #: IvarCache
    attr_accessor :cover #: word
    attr_accessor :direct #: ptr
    attr_accessor :concealed #: word
  end

  class CEntry < Layout
    attr_accessor :id #: word
    attr_accessor :value #: value
    attr_accessor :file #: ptr
    attr_accessor :file_len #: word
    attr_accessor :line #: word
    attr_accessor :private #: word
    attr_accessor :deprecated #: word
    attr_accessor :owner #: value
    attr_accessor :concealed #: word
  end
  # A compiled method takes `(recv, argc, argv, entry, blk, found)`: its
  # own entry, whose name and cref its frame records, and the ancestor list
  # node where the lookup found it. A builtin takes
  # `(recv, argc, argv, cref, blk)`. A direct entry takes
  # `(recv, entry, blk, found, ...)` plus up to four arguments in
  # registers, with one signature for each count.
  module Method
    #: (ptr, value, word, ptr, ptr, value, value) -> value
    def self.call(fn, v1, n, p1, p2, v2, v3) = Machine.indirect
  end

  module Builtin
    #: (ptr, value, word, ptr, value, value) -> value
    def self.call(fn, v1, n, p, v2, v3) = Machine.indirect
  end

  module Direct0
    #: (ptr, value, ptr, value, value) -> value
    def self.call(fn, v1, p, v2, v3) = Machine.indirect
  end

  module Direct1
    #: (ptr, value, ptr, value, value, value) -> value
    def self.call(fn, v1, p, v2, v3, v4) = Machine.indirect
  end

  module Direct2
    #: (ptr, value, ptr, value, value, value, value) -> value
    def self.call(fn, v1, p, v2, v3, v4, v5) = Machine.indirect
  end

  module Direct3
    #: (ptr, value, ptr, value, value, value, value, value) -> value
    def self.call(fn, v1, p, v2, v3, v4, v5, v6) = Machine.indirect
  end

  module Direct4
    #: (ptr, value, ptr, value, value, value, value, value, value) -> value
    def self.call(fn, v1, p, v2, v3, v4, v5, v6, v7) = Machine.indirect
  end
  # Method kinds other than a compiled def and a builtin. Accessors keep
  # the ivar's id in `fn`.
  KIND_ATTR_READER = 3
  KIND_ATTR_WRITER = 4
  # A builtin that makes no frame of its own: `Proc#call` and `send`,
  # which CRuby does not show in a backtrace.
  KIND_FRAMELESS = 5
  # An `undef`: the name has no method from here down the ancestor list.
  KIND_UNDEF = 6
  # A Method for a name that `respond_to_missing?` claimed: a call goes to
  # `method_missing`.
  KIND_MISSING = 9

  #: (word, value, value) -> value
  def zr_class_alloc(type, sup, klass)
    c = zr_alloc(type, klass, RClass.size)
    RClass[c].name = Machine.value(QNIL)
    RClass[c].superclass = sup
    RClass[c].attached = Machine.value(QNIL)
    RClass[c].origin = Machine.value(QNIL)
    ext = zr_xmalloc(ClassExt.size)
    ClassExt[ext].mtab = 0
    ClassExt[ext].mlen = 0
    ClassExt[ext].mcap = 0
    ClassExt[ext].ctab = 0
    ClassExt[ext].clen = 0
    ClassExt[ext].ccap = 0
    ClassExt[ext].cidx = 0
    ClassExt[ext].cbins = 0
    zr_ivtab_init(Machine.ptr(ClassExt[ext].iv))
    zr_ivtab_init(Machine.ptr(ClassExt[ext].cv))
    ClassExt[ext].refined = Machine.value(QNIL)
    ClassExt[ext].active = Machine.value(QNIL)
    ClassExt[ext].boxed = Machine.value(QNIL)
    ClassExt[ext].shadow = Machine.value(QNIL)
    ClassExt[ext].alloc = 0
    ClassExt[ext].saved = 0
    ClassExt[ext].slen = 0
    ClassExt[ext].supers = 0
    ClassExt[ext].rank = 0
    ClassExt[ext].midx = 0
    ClassExt[ext].mbins = 0
    ClassExt[ext].obj_bytes = RObject.size
    counter = Machine.static(:class_serial, 8)
    Machine.store64(counter, 0, Machine.load64(counter, 0) + 1)
    ClassExt[ext].serial = Machine.load64(counter, 0)
    RClass[c].ext = ext
    zr_methods_changed()
    # Builds the rank table at creation, if Object exists. Then a site's
    # type check can use the table at its first call. A class from
    # `Class.allocate` has no ancestor list yet (its rank stays 0) and gets
    # its table when its superclass is set.
    if type == T_CLASS && sup != QNIL && zr_global(G_OBJECT) != QFALSE
      zr_class_rank(c)
    end
    if zr_program_started_p() && zr_hidden_now()
      RBasic[c].flags = RBasic[c].flags | FL_CONCEALED
    end
    c
  end

  # The three superclasses that ruby refuses, in `rb_check_inheritable`'s
  # order. Returns QUNDEF if it raised.
  #: (value) -> value
  def zr_check_inheritable(sup)
    if zr_special_p(sup) || zr_type(sup) != T_CLASS
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("superclass must be an instance of Class (given an instance of "), 62)
      zr_buf_class_of(b, sup)
      zr_buf_byte(b, 41)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if zr_singleton_p(sup)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of singleton class"), 38)
    end
    if sup == zr_global(G_CLASS)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of Class"), 28)
    end
    Machine.value(QNIL)
  end

  # A class with no metaclass yet: a builtin class gets one on first use,
  # as `zr_singleton_class` makes any.
  #: (value) -> value
  def zr_class_boot(sup)
    zr_class_alloc(T_CLASS, sup, zr_global(G_CLASS))
  end

  # A class with its metaclass, as CRuby makes each class. The metaclass
  # inherits from the superclass's, so class methods are inherited too.
  #: (value) -> value
  def zr_class_new(sup)
    c = zr_class_boot(sup)
    zr_make_metaclass(c)
    c
  end

  T_ICLASS = 28

  # Whether `klass`'s ancestor list contains `mod`, directly or as a proxy.
  #: (value, value) -> bool
  def zr_chain_includes(klass, mod)
    k = klass
    while k != QNIL
      if k == mod || ((RBasic[k].flags & T_MASK) == T_ICLASS && RClass[k].attached == mod)
        return true
      end
      k = RClass[k].superclass
    end
    false
  end

  # Makes a proxy for the ancestor list node `node` (a module, or a proxy
  # of one) before `sup`, which shares the node's tables.
  #: (value, value) -> value
  def zr_iclass_new(node, sup)
    mod = zr_type(node) == T_ICLASS ? RClass[node].attached : node
    ic = zr_alloc(T_ICLASS, mod, RClass.size)
    RClass[ic].name = Machine.value(QNIL)
    RClass[ic].superclass = sup
    RClass[ic].ext = RClass[node].ext
    RClass[ic].attached = mod
    RClass[ic].origin = Machine.value(QNIL)
    zr_methods_changed()
    ic
  end

  # The location of a class's own methods: its origin proxy if something
  # is prepended, else the class.
  #: (value) -> value
  def zr_origin(klass)
    if RClass[klass].origin != QNIL
      return RClass[klass].origin
    end
    klass
  end

  # CRuby's include_modules_at: inserts a proxy for each node of `mod`'s
  # ancestor list after `at`, except for a node whose tables `klass`'s
  # ancestor list already contains. An include (`whole`) searches the full
  # list and moves the insertion point to the node that it finds, unless a
  # superclass contains it. A prepend searches only down to `klass`'s
  # origin. The proxy of a module's origin becomes the origin of the proxy
  # of its head, as in the module.
  #: (value, value, value, bool) -> void
  def zr_splice_modules(klass, at, mod, whole)
    klass_origin = zr_origin(klass)
    c = at
    heads = zr_ary_new(2)
    m = mod
    while m != QNIL
      found = false
      if klass_origin != c || whole
        c_seen = klass == c
        class_seen = false
        p = RClass[klass].superclass
        while p != QNIL && !found
          if klass_origin == p && !whole
            p = Machine.value(QNIL)
          else
            c_seen = true if c == p
            if zr_type(p) == T_ICLASS
              if RClass[p].ext == RClass[m].ext
                c = p if c_seen && !class_seen
                found = true
              end
            elsif zr_type(p) == T_CLASS
              class_seen = true
            end
            p = RClass[p].superclass unless found
          end
        end
      end
      unless found
        ic = zr_iclass_new(m, RClass[c].superclass)
        RClass[c].superclass = ic
        c = ic
        n = RArray[heads].len
        if RClass[m].origin != QNIL
          zr_ary_push(heads, ic)
          zr_ary_push(heads, RClass[m].origin)
        elsif n > 0 && zr_ary_at(heads, n - 1) == m
          RClass[zr_ary_at(heads, n - 2)].origin = ic
          RArray[heads].len = n - 2
        end
      end
      m = RClass[m].superclass
    end
    zr_methods_changed()
    zr_gates_recheck(0)
  end

  # The proxies of `mod` in other ancestor lists, newest first, in the
  # order of CRuby's subclass list of a module.
  #: (value) -> value
  def zr_proxies_of(mod)
    out = zr_ary_new(4)
    a = 0
    while a < Heap[zr_heap()].arenas
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead[base].cell
      i = zr_arena_next_allocated(base, 0)
      while i < ARENA_CELLS
        cell = first + (i * bytes)
        if (Machine.load64(cell, 0) & T_MASK) == T_ICLASS
          ic = Machine.value(cell)
          if RClass[ic].attached == mod && RClass[mod].origin != ic
            zr_ary_unshift(out, ic)
          end
        end
        i = zr_arena_next_allocated(base, i + 1)
      end
      a += 1
    end
    out
  end

  # `include`: inserts `mod`'s ancestor list after `klass`'s origin, and
  # after each proxy of `klass` in other ancestor lists that do not have it.
  #: (value, value) -> void
  def zr_include_module(klass, mod)
    zr_splice_modules(klass, zr_origin(klass), mod, true)
    if zr_type(klass) != T_MODULE
      return
    end
    proxies = zr_proxies_of(klass)
    i = 0
    while i < RArray[proxies].len
      ic = zr_ary_at(proxies, i)
      unless zr_chain_includes(ic, mod)
        zr_splice_modules(ic, zr_origin(ic), mod, true)
      end
      i += 1
    end
  end

  # Moves the class's methods to an origin proxy directly below it, where
  # `super` from them starts. Does nothing if it has one.
  #: (value) -> bool
  def zr_ensure_origin(klass)
    if RClass[klass].origin != QNIL
      return false
    end
    o = zr_iclass_new(klass, RClass[klass].superclass)
    ext = zr_xmalloc(ClassExt.size)
    zr_memcpy(ext, RClass[klass].ext, ClassExt.size)
    ClassExt[ext].ctab = 0
    ClassExt[ext].clen = 0
    ClassExt[ext].ccap = 0
    ClassExt[ext].cidx = 0
    ClassExt[ext].cbins = 0
    zr_ivtab_init(Machine.ptr(ClassExt[ext].iv))
    zr_ivtab_init(Machine.ptr(ClassExt[ext].cv))
    RClass[o].ext = ext
    ClassExt[RClass[klass].ext].mtab = 0
    ClassExt[RClass[klass].ext].mlen = 0
    ClassExt[RClass[klass].ext].mcap = 0
    # The table's index moves with the table, to the origin's copy.
    ClassExt[RClass[klass].ext].midx = 0
    ClassExt[RClass[klass].ext].mbins = 0
    ClassExt[RClass[klass].ext].saved = 0
    ClassExt[RClass[klass].ext].slen = 0
    i = 0
    while i < ClassExt[ext].mlen
      e = ClassExt[ext].mtab + (i * MEntry.size)
      if MEntry[e].meta != 0 && FrameMeta[MEntry[e].meta].owner == klass
        FrameMeta[MEntry[e].meta].owner = o
      end
      i += 1
    end
    RClass[klass].superclass = o
    RClass[klass].origin = o
    zr_methods_changed()
    true
  end

  # `prepend`: inserts `mod`'s ancestor list between `klass` and its
  # origin, and between each proxy of `klass` and that proxy's origin. A
  # proxy made before the module had an origin gets one here.
  #: (value, value) -> void
  def zr_prepend_module(klass, mod)
    fresh = zr_ensure_origin(klass)
    zr_splice_modules(klass, klass, mod, false)
    if zr_type(klass) != T_MODULE
      return
    end
    proxies = zr_proxies_of(klass)
    i = 0
    while i < RArray[proxies].len
      ic = zr_ary_at(proxies, i)
      if fresh && RClass[ic].origin == QNIL
        o = zr_iclass_new(RClass[klass].origin, RClass[ic].superclass)
        RClass[ic].superclass = o
        RClass[ic].origin = o
      end
      zr_splice_modules(ic, ic, mod, false)
      i += 1
    end
  end

  # `prepend_features(base)`: puts the module (self) before `base`'s own
  # methods. The core's `prepend` calls it for each module, then `prepended`.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_prepend_features(recv, argc, argv, cref, blk)
    base = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(base) || (zr_type(base) != T_CLASS && zr_type(base) != T_MODULE)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_class_of(b, base)
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if zr_modify_frozen_p(base)
      return zr_frozen_error(base)
    end
    if recv == base || zr_chain_includes(recv, base)
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("cyclic prepend detected"), 23)
    end
    zr_prepend_module(base, recv)
    recv
  end

  # Calls a hook such as `included` or `inherited`: `recv.mid(arg)`,
  # private or not.
  #: (value, word, value) -> value
  def zr_hook(recv, mid, arg)
    if zr_hidden_now() && zr_program_hook_p(recv, mid)
      return Machine.value(QNIL)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(arg))
    zr_send(recv, mid, 1, slot)
  end

  # Whether the method that answers hook `mid` on `recv` is the program's
  # own. What eval support defines never reaches one, as ruby's compiler
  # defines nothing; its own hooks and the core library's still run.
  #: (value, word) -> bool
  def zr_program_hook_p(recv, mid)
    e = zr_find_method(zr_class_of(recv), mid)
    if e == 0 || MEntry[e].core != 0
      return false
    end
    meta = MEntry[e].meta
    meta == 0 || FrameMeta[meta].hidden == 0
  end

  #: (value) -> value
  def zr_check_module(m)
    if zr_special_p(m) || zr_type(m) != T_MODULE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_class_of(b, m)
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    Machine.value(QNIL)
  end

  # `append_features(base)`: inserts the module (self) into `base`. The
  # core's `include` calls it for each module, then `included`.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_append_features(recv, argc, argv, cref, blk)
    base = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(base) || (zr_type(base) != T_CLASS && zr_type(base) != T_MODULE)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_class_of(b, base)
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if zr_modify_frozen_p(base)
      return zr_frozen_error(base)
    end
    if recv == base || zr_chain_includes(recv, base)
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("cyclic include detected"), 23)
    end
    zr_include_module(base, recv)
    recv
  end

  # `extend`: adds each module to the singleton class, then calls its
  # `extended` hook.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_extend(recv, argc, argv, cref, blk)
    if argc == 0
      return zr_wrong_arity_min(0, 1)
    end
    i = argc - 1
    while i >= 0
      m = Machine.value(Machine.load64(argv + (i * 8), 0))
      r = zr_check_module(m)
      return r if r == QUNDEF
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(recv))
      r = zr_send(m, Machine.id(:extend_object), 1, slot)
      return r if r == QUNDEF
      r = zr_hook(m, Machine.id(:extended), recv)
      return r if r == QUNDEF
      i -= 1
    end
    recv
  end

  # `Module#extend_object`: adds the module to the object's singleton
  # class. A module can override it to see each object that it extends.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_extend_object(recv, argc, argv, cref, blk)
    obj = Machine.value(Machine.load64(argv, 0))
    s = zr_singleton_class(obj)
    return s if s == QUNDEF
    if !zr_special_p(obj) && zr_frozen_p(obj)
      return zr_frozen_error(obj)
    end
    zr_include_module(s, recv)
    obj
  end

  # `alias :"#{a}" :"#{b}"`: the names come as values.
  #: (value, value, value) -> value
  def zr_alias_value(klass, new_name, old_name)
    made = Machine.slot(8)
    had = Machine.slot(8)
    r = zr_name_id(new_name, made)
    return r if r == QUNDEF
    r = zr_name_id(old_name, had)
    return r if r == QUNDEF
    zr_alias(klass, Machine.load64(made, 0), Machine.load64(had, 0))
  end

  # `alias new old` and `alias_method`: the old entry again under the new
  # name. It keeps its meta, so a backtrace shows the original name.
  #: (value, word, word) -> value
  def zr_alias(klass, new_id, old_id)
    if zr_modify_frozen_p(klass)
      return zr_frozen_error(klass)
    end
    e = zr_find_method(klass, old_id)
      # A module's ancestor list is only the module, so the lookup then
      # tries Object's methods (and Kernel's), as rb_alias does.
    if e == 0 && zr_type(klass) == T_MODULE
      e = zr_find_method(zr_global(G_OBJECT), old_id)
    end
    if e == 0
        # With the name and the receiver, which did_you_mean reads.
      return zr_undefined_method(klass, old_id, VIS_PUBLIC)
    end
    zr_method_copy(klass, new_id, e, MEntry[e].meta, MEntry[e].vis, true)
    zr_method_added(klass, new_id)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_alias_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(16)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    r = zr_name_id(Machine.value(Machine.load64(argv, 8)), slot + 8)
    return r if r == QUNDEF
    new_id = Machine.load64(slot, 0)
    r = zr_alias(recv, new_id, Machine.load64(slot, 8))
    return r if r == QUNDEF
    zr_sym(new_id)
  end

  # `undef name`: an entry that stops the search. Thus the name is removed
  # from this class and its subclasses, even where an ancestor has it.
  # `undef :"#{a}"`: the name comes as a value.
  #: (value, value) -> value
  def zr_undef_value(klass, name)
    slot = Machine.slot(8)
    r = zr_name_id(name, slot)
    return r if r == QUNDEF
    zr_undef(klass, Machine.load64(slot, 0))
  end

  #: (value, word) -> value
  def zr_undef(klass, id)
    if zr_modify_frozen_p(klass)
      return zr_frozen_error(klass)
    end
    if zr_find_method(klass, id) == 0
      # With the name and the receiver, which did_you_mean reads.
      return zr_undefined_method(klass, id, VIS_PUBLIC)
    end
    zr_method_add(klass, id, 0, 0, KIND_UNDEF, 0, Machine.value(QNIL))
    zr_method_undefined(klass, id)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_undef_method(recv, argc, argv, cref, blk)
    slot = Machine.slot(8)
    i = 0
    while i < argc
      r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
      return r if r == QUNDEF
      r = zr_undef(recv, Machine.load64(slot, 0))
      return r if r == QUNDEF
      i += 1
    end
    recv
  end

  # `Module#===`: whether the object is an instance of the module.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_eqq(recv, argc, argv, cref, blk)
    zr_bool(zr_is_a(Machine.value(Machine.load64(argv, 0)), recv))
  end

  # The class that a class variable belongs to under `cref`: the innermost
  # class, or for a singleton class, the object it is attached to. The top
  # level has none, but a `class Object` body has one.
  #: (value) -> value
  def zr_cvar_base(cref)
    cref = zr_cref_lexical(cref)
    if cref == zr_global(G_TOP_CREF)
      return Machine.value(QNIL)
    end
    k = zr_cref_klass(cref)
    while zr_singleton_p(k)
      k = RClass[k].attached
      if zr_special_p(k) || (zr_type(k) != T_CLASS && zr_type(k) != T_MODULE)
        return Machine.value(QNIL)
      end
    end
    k
  end

  # The class in `klass`'s ancestor list whose table contains `id`, or nil.
  #: (value, word) -> value
  def zr_cvar_owner(klass, id)
    k = klass
    while k != QNIL
      if zr_ivtab_row(Machine.ptr(ClassExt[RClass[k].ext].cv), id) != 0
        return k
      end
      k = RClass[k].superclass
    end
    Machine.value(QNIL)
  end

  # Whether Refinement#import_methods can copy `name` from `mod`: true for
  # a program's `def`, false for an attr, a define_method, an alias or a
  # builtin, and nil for a core method written in Ruby, which the caller
  # looks up among CRuby's own Ruby methods.
  #: (value, value) -> value
  def zr_mod_import_ok_p(mod, name)
    id = zr_sym2id(name)
    e = zr_find_method(mod, id)
    if e == 0 || MEntry[e].kind != KIND_DEF || MEntry[e].orig != id
      return Machine.value(QFALSE)
    end
    if MEntry[e].core != 0
      return Machine.value(QNIL)
    end
    Machine.value(QTRUE)
  end

  # rb_cvar_get's lookup: the value belongs to the farthest ancestor that
  # has the name. A nearer class that also has it is "overtaken" and
  # raises; a nearer copy in the same module is removed (cvar_overtaken).
  # Returns nil when no ancestor has the name.
  #: (value, word) -> value
  def zr_cvar_target(klass, id)
    front = Machine.value(QNIL)
    target = Machine.value(QNIL)
    k = klass
    while k != QNIL
      if zr_ivtab_row(Machine.ptr(ClassExt[RClass[k].ext].cv), id) != 0
        if front == QNIL
          front = k
        end
        target = k
      end
      k = RClass[k].superclass
    end
    if front == QNIL || target == front
      return target
    end
    near = zr_type(front) == T_ICLASS ? RClass[front].attached : front
    far = zr_type(target) == T_ICLASS ? RClass[target].attached : target
    if near != far
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("class variable "), 15)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" of "), 4)
      zr_buf_class(b, near)
      zr_buf_push(b, Machine.bytes(" is overtaken by "), 17)
      zr_buf_class(b, far)
      return zr_raise_buf(zr_global(G_RUNTIME_ERROR), b)
    end
    if zr_type(front) == T_CLASS
      t = Machine.ptr(ClassExt[RClass[front].ext].cv)
      e = zr_ivtab_row(t, id)
      last = IvTab[t].rows + ((IvTab[t].len - 1) * IvEntry.size)
      if e != last
        zr_memmove(e, e + IvEntry.size, last - e)
      end
      IvTab[t].len = IvTab[t].len - 1
    end
    target
  end

  #: (value, word) -> value
  def zr_cvar_get(cref, id)
    base = zr_cvar_base(cref)
    if base == QNIL
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
    end
    owner = zr_cvar_target(base, id)
    return owner if owner == QUNDEF
    if owner == QNIL
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("uninitialized class variable "), 29)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes(" in "), 4)
      zr_buf_class(b, base)
      return zr_raise_buf(zr_global(G_NAME_ERROR), b)
    end
    r = zr_ractor_cvar_check(owner, id)
    return r if r == QUNDEF
    zr_ivtab_get(Machine.ptr(ClassExt[RClass[owner].ext].cv), id)
  end

  # A class variable outside the main ractor: CRuby refuses all of them.
  #: (value, word) -> value
  def zr_ractor_cvar_check(owner, id)
    if Task[zr_task()].ractor == 0
      return Machine.value(QNIL)
    end
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_sym(id)))
    Machine.store64(args, 8, Machine.word(owner))
    zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:cvar_isolation!), 2, args)
  end

  # Whether `@@id` is set under `cref`.
  #: (value, word) -> value
  def zr_cvar_defined(cref, id)
    base = zr_cvar_base(cref)
    if base == QNIL
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
    end
    zr_bool(zr_cvar_owner(base, id) != QNIL)
  end

  #: (value, word, value) -> value
  def zr_cvar_set(cref, id, v)
    base = zr_cvar_base(cref)
    if base == QNIL
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
    end
    owner = zr_cvar_target(base, id)
    return owner if owner == QUNDEF
    if owner == QNIL
      owner = base
    end
    r = zr_ractor_cvar_check(owner, id)
    return r if r == QUNDEF
    frozen = zr_class_modify_check(owner)
    return frozen if frozen == QUNDEF
    zr_ivtab_set(Machine.ptr(ClassExt[RClass[owner].ext].cv), id, v)
    zr_write_barrier(owner, v)
    v
  end

  # `@@name` for the tree-walking interpreter, which has a Symbol where
  # compiled code has an id. It uses the kernel's lookup, so a string that
  # it evaluates reads and writes the same class variable as compiled code.
  #: (value, value) -> value
  def zr_cvar_get_m(cref, name)
    zr_cvar_get(cref, zr_sym2id(name))
  end

  #: (value, value) -> value
  def zr_cvar_defined_m(cref, name)
    zr_cvar_defined(cref, zr_sym2id(name))
  end

  #: (value, value, value) -> value
  def zr_cvar_set_m(cref, name, v)
    zr_cvar_set(cref, zr_sym2id(name), v)
  end

  # `Module#ancestors`: the ancestor list, with each proxy as its module.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_ancestors(recv, argc, argv, cref, blk)
    out = zr_ary_new(8)
    k = recv
    while k != QNIL
      if RClass[k].origin == QNIL
        zr_ary_push(out, zr_type(k) == T_ICLASS ? RClass[k].attached : k)
      end
      k = RClass[k].superclass
    end
    out
  end

  # `Module#include?`: whether `mod` is in the ancestor list, other than as
  # itself.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_include_p(recv, argc, argv, cref, blk)
    m = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(m) || zr_type(m) != T_MODULE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_class_of(b, m)
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    zr_bool(m != recv && zr_chain_includes(recv, m))
  end

  #: (value) -> bool
  def zr_singleton_p(klass)
    (RBasic[klass].flags & FL_SINGLETON) != 0
  end

  # Makes the singleton class of the class `klass`. Its superclass is the
  # superclass's singleton class, or Class for a root. From now on it is
  # `klass`'s class.
  #: (value) -> value
  def zr_make_metaclass(klass)
    sup = RClass[klass].superclass
    while sup != QNIL && zr_type(sup) == T_ICLASS
      sup = RClass[sup].superclass
    end
    if sup == QNIL
      msup = zr_global(G_CLASS)
    else
      msup = zr_singleton_class(sup)
    end
    meta = zr_class_alloc(T_CLASS, msup, zr_global(G_CLASS))
    # A singleton class is frozen when its object is frozen.
    RBasic[meta].flags = RBasic[meta].flags | FL_SINGLETON | (RBasic[klass].flags & FL_FREEZE)
    RClass[meta].attached = klass
    RBasic[klass].klass = meta
    meta
  end

  # Whether `v` can have no singleton class: an Integer, a Float, a
  # Symbol, or a String in the fstring table, which CRuby's
  # rb_singleton_class refuses. nil, true and false use their own class.
  #: (value) -> bool
  def zr_singleton_refused_p(v)
    if zr_special_p(v)
      return v != QNIL && v != QTRUE && v != QFALSE
    end
    zr_big_p(v) || zr_type(v) == T_FLOAT || zr_type(v) == T_SYMBOL || (zr_type(v) == T_STRING && (RBasic[v].flags & FL_FSTR) != 0)
  end

  # The singleton class of `v`, made on first use.
  #: (value) -> value
  def zr_singleton_class(v)
    if zr_singleton_refused_p(v)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
    end
    if zr_special_p(v)
      return zr_class_of(v)
    end
    k = RBasic[v].klass
    if zr_singleton_p(k) && RClass[k].attached == v
      return k
    end
    if zr_type(v) == T_CLASS
      return zr_make_metaclass(v)
    end
    s = zr_class_alloc(T_CLASS, k, zr_global(G_CLASS))
    RBasic[s].flags = RBasic[s].flags | FL_SINGLETON | (RBasic[v].flags & FL_FREEZE)
    RClass[s].attached = v
    RBasic[v].klass = s
    s
  end

  # Checks before a change to a class's own tables: its own frozen flag,
  # never its origin's. The error for a frozen singleton class shows the
  # object it belongs to, as CRuby's rb_class_modify_check does.
  #: (value) -> value
  def zr_class_modify_check(klass)
    if !zr_frozen_p(klass)
      return Machine.value(QNIL)
    end
    zr_frozen_error(zr_singleton_p(klass) ? RClass[klass].attached : klass)
  end

  # The class that `v.class` returns: it skips a singleton class and the
  # proxies of the modules that the object extends.
  #: (value) -> value
  def zr_real_class(v)
    k = zr_class_of(v)
    while zr_singleton_p(k) || zr_type(k) == T_ICLASS
      k = RClass[k].superclass
    end
    k
  end

  # Whether `v`'s class is `klass` with no singleton class of `v` in
  # between, as CRuby's `CLASS_OF(v) == klass` tests.
  #: (value, value) -> value
  def zr_class_of_is(v, klass)
    zr_bool(zr_class_of(v) == klass)
  end

  # The path of `v`'s class (zr_class_path), always as a String, for a
  # message.
  #: (value) -> value
  def zr_class_name_of(v)
    zr_class_path(zr_real_class(v))
  end

  #: () -> value
  def zr_module_new
    zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_MODULE))
  end

  # The gate bit that a redefinition of an operator sets, or 0.
  #: (value, word) -> word
  def zr_gate_bit(klass, mid)
    if klass == zr_global(G_INTEGER)
      if mid == Machine.id(:+)
        GATE_PLUS
      elsif mid == Machine.id(:-)
        GATE_MINUS
      elsif mid == Machine.id(:*)
        GATE_MUL
      elsif mid == Machine.id(:/)
        GATE_DIV
      elsif mid == Machine.id(:%)
        GATE_MOD
      elsif mid == Machine.id(:<)
        GATE_LT
      elsif mid == Machine.id(:<=)
        GATE_LE
      elsif mid == Machine.id(:>)
        GATE_GT
      elsif mid == Machine.id(:>=)
        GATE_GE
      elsif mid == Machine.id(:==)
        GATE_EQ
      elsif mid == Machine.id(:!=)
        GATE_NE
      elsif mid == Machine.id(:&)
        GATE_AND
      elsif mid == Machine.id(:|)
        GATE_OR
      elsif mid == Machine.id(:^)
        GATE_XOR
      elsif mid == Machine.id(:>>)
        GATE_SHR
      elsif mid == Machine.id(:succ)
        GATE_SUCC
      elsif mid == Machine.id(:times)
        GATE_TIMES
      elsif mid == Machine.id(:upto)
        GATE_UPTO
      elsif mid == Machine.id(:-@)
        GATE_UMINUS
      elsif mid == Machine.id(:<=>)
        GATE_CMP
      else
        0
      end
    elsif klass == zr_global(G_FLOAT)
      if mid == Machine.id(:+)
        GATE_FLO_PLUS
      elsif mid == Machine.id(:-)
        GATE_FLO_MINUS
      elsif mid == Machine.id(:*)
        GATE_FLO_MUL
      elsif mid == Machine.id(:/)
        GATE_FLO_DIV
      elsif mid == Machine.id(:<)
        GATE_FLO_LT
      elsif mid == Machine.id(:<=)
        GATE_FLO_LE
      elsif mid == Machine.id(:>)
        GATE_FLO_GT
      elsif mid == Machine.id(:>=)
        GATE_FLO_GE
      elsif mid == Machine.id(:==)
        GATE_FLO_EQ
      elsif mid == Machine.id(:-@)
        GATE_FLO_UMINUS
      else
        0
      end
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
      GATE_AREF
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
      GATE_ASET
    elsif klass == zr_global(G_HASH) && mid == Machine.id(:[])
      GATE_HASH_AREF
    elsif klass == zr_global(G_HASH) && mid == Machine.id(:[]=)
      GATE_HASH_ASET
    elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
      GATE_LTLT
    elsif klass == zr_global(G_STRING) && mid == Machine.id(:freeze)
      GATE_FREEZE
    elsif klass == zr_global(G_STRING) && mid == Machine.id(:getbyte)
      GATE_GETBYTE
    elsif klass == zr_global(G_STRING) && mid == Machine.id(:setbyte)
      GATE_SETBYTE
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:push)
      GATE_PUSH
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:pop)
      GATE_POP
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:shift)
      GATE_SHIFT
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:empty?)
      GATE_EMPTY_P
    elsif klass == zr_global(G_PROC) && mid == Machine.id(:call)
      GATE_PROC_CALL
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:each)
      GATE_EACH
    elsif klass == zr_global(G_MATH_META) && zr_math_inline_p(mid)
      GATE_MATH
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:map)
      GATE_MAP
    elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:select)
      GATE_SELECT
    elsif klass == zr_global(G_RANGE) && mid == Machine.id(:each)
      GATE_RANGE_EACH
    elsif klass == zr_global(G_SYMBOL) && mid == Machine.id(:===)
      GATE_SYM_EQQ
    elsif mid == Machine.id(:!) && zr_not_gated_p(klass)
      GATE_NOT
    else
      0
    end
  end

  # The classes whose `!` an inline `not` replaces: nil, true and false
  # run inline while none of their ancestors redefines `!`.
  #: (value) -> bool
  def zr_not_gated_p(klass)
    klass == zr_global(G_NIL) || klass == zr_global(G_TRUE) || klass == zr_global(G_FALSE) ||
      klass == zr_global(G_OBJECT) || klass == zr_global(G_KERNEL) || klass == zr_global(G_BASIC_OBJECT)
  end

  # The operators that compiled code inlines, as they were at program
  # start: the class the gate guards (a global's index), the name, the
  # gate bit, and the body and visibility that the class found then.
  class GateRow < Layout
    attr_accessor :klass #: word
    attr_accessor :mid #: word
    attr_accessor :bit #: word
    attr_accessor :fn #: ptr
    attr_accessor :vis #: word
  end

  GATE_ROWS = 56

  #: (word, word, word, word) -> word
  def zr_gate_row(i, klass, mid, bit)
    row = Machine.static(:gate_rows, GATE_ROWS * GateRow.size) + (i * GateRow.size)
    GateRow[row].klass = klass
    GateRow[row].mid = mid
    GateRow[row].bit = bit
    e = zr_search_method(zr_global(klass), mid)
    if e != 0
      GateRow[row].fn = zr_entry_body(e)
      GateRow[row].vis = MEntry[e].vis
    end
    i + 1
  end

  # Runs at program start, after the runtime's own definitions. From now
  # on, a change to what an entry's class finds closes that entry's gate.
  #: () -> void
  def zr_gates_snapshot
    zr_set_global(G_MATH_META, zr_singleton_class(zr_core_class(Machine.id(:Math))))
    i = zr_gate_row(0, G_INTEGER, Machine.id(:+), GATE_PLUS)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:-), GATE_MINUS)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:*), GATE_MUL)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:/), GATE_DIV)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:%), GATE_MOD)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:<), GATE_LT)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:<=), GATE_LE)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:>), GATE_GT)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:>=), GATE_GE)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:==), GATE_EQ)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:!=), GATE_NE)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:&), GATE_AND)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:|), GATE_OR)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:^), GATE_XOR)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:>>), GATE_SHR)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:[]), GATE_AREF)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:[]=), GATE_ASET)
    i = zr_gate_row(i, G_HASH, Machine.id(:[]), GATE_HASH_AREF)
    i = zr_gate_row(i, G_HASH, Machine.id(:[]=), GATE_HASH_ASET)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:<<), GATE_LTLT)
    i = zr_gate_row(i, G_STRING, Machine.id(:<<), GATE_LTLT)
    i = zr_gate_row(i, G_STRING, Machine.id(:freeze), GATE_FREEZE)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:+), GATE_FLO_PLUS)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:-), GATE_FLO_MINUS)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:*), GATE_FLO_MUL)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:/), GATE_FLO_DIV)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:<), GATE_FLO_LT)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:<=), GATE_FLO_LE)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:>), GATE_FLO_GT)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:>=), GATE_FLO_GE)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:==), GATE_FLO_EQ)
    i = zr_gate_row(i, G_STRING, Machine.id(:getbyte), GATE_GETBYTE)
    i = zr_gate_row(i, G_STRING, Machine.id(:setbyte), GATE_SETBYTE)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:succ), GATE_SUCC)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:push), GATE_PUSH)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:pop), GATE_POP)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:shift), GATE_SHIFT)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:empty?), GATE_EMPTY_P)
    i = zr_gate_row(i, G_PROC, Machine.id(:call), GATE_PROC_CALL)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:each), GATE_EACH)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:map), GATE_MAP)
    i = zr_gate_row(i, G_ARRAY, Machine.id(:select), GATE_SELECT)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:times), GATE_TIMES)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:upto), GATE_UPTO)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:sqrt), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:cbrt), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:sin), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:cos), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:tan), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:atan), GATE_MATH)
    i = zr_gate_row(i, G_MATH_META, Machine.id(:exp), GATE_MATH)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:-@), GATE_UMINUS)
    i = zr_gate_row(i, G_FLOAT, Machine.id(:-@), GATE_FLO_UMINUS)
    i = zr_gate_row(i, G_INTEGER, Machine.id(:<=>), GATE_CMP)
    i = zr_gate_row(i, G_SYMBOL, Machine.id(:===), GATE_SYM_EQQ)
    zr_gate_row(i, G_RANGE, Machine.id(:each), GATE_RANGE_EACH)
    Machine.store64(Machine.static(:gates_taken, 8), 0, 1)
  end

  # Runs after a definition, a visibility change, a removal, or a module
  # inserted into an ancestor list. The gate of each entry whose class now
  # finds a different body or visibility for the name closes, and each
  # site of that operator then makes the call. `mid` 0 checks all entries.
  # A gate never opens again. The walk leaves `Task.found` as the send
  # that called it left it.
  #: (word) -> void
  def zr_gates_recheck(mid)
    if Machine.load64(Machine.static(:gates_taken, 8), 0) == 0
      return
    end
    found = Task[zr_task()].found
    rows = Machine.static(:gate_rows, GATE_ROWS * GateRow.size)
    i = 0
    while i < GATE_ROWS
      row = rows + (i * GateRow.size)
      if (mid == 0 || GateRow[row].mid == mid) && (Machine.gates & GateRow[row].bit) == 0
        e = zr_search_method(zr_global(GateRow[row].klass), GateRow[row].mid)
        if e == 0 || zr_entry_body(e) != GateRow[row].fn || MEntry[e].vis != GateRow[row].vis
          Machine.gates_set(Machine.gates | GateRow[row].bit)
        end
      end
      i += 1
    end
    Task[zr_task()].found = found
  end

  # A definition. The first one of each builtin operator is the runtime's
  # own and leaves the gate clear; a later one sets it. `meta` is the
  # compiled def's own FrameMeta, or 0 for a builtin, which gets one here.
  #: (value, word, ptr, word, word, ptr, value) -> value
  def zr_define_method(klass, mid, fn, arity, kind, meta, cref)
    zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, cref))
  end

  # A def with a direct entry (MEntry.direct): `fn` is zr_direct_fn, and
  # `direct` is the body. The direct entry waits in a static word, because
  # the entry's eight fields already fill the argument registers.
  # zr_define_method_as reads and clears it before any hook runs, because
  # `method_added` can call the method.
  #: (value, word, ptr, ptr, word, word, ptr, value) -> value
  def zr_define_method_direct(klass, mid, fn, direct, arity, kind, meta, cref)
    Machine.store64(zr_direct_pending(), 0, Machine.word(direct))
    zr_define_method(klass, mid, fn, arity, kind, meta, cref)
  end

  #: (value, word, ptr, ptr, word, word, ptr, value) -> value
  def zr_define_method_public_direct(klass, mid, fn, direct, arity, kind, meta, cref)
    Machine.store64(zr_direct_pending(), 0, Machine.word(direct))
    zr_define_method_public(klass, mid, fn, arity, kind, meta, cref)
  end

  #: () -> ptr
  def zr_direct_pending
    Machine.static(:direct_pending, 8)
  end

  # The body of `e`, which identifies a method: its direct entry if it has
  # one (because each such def's `fn` is zr_direct_fn), else its `fn`.
  #: (ptr) -> ptr
  def zr_entry_body(e)
    direct = MEntry[e].direct
    direct != 0 ? direct : MEntry[e].fn
  end

  # `def obj.name`, and a def in a method body: public, whatever the
  # scope's visibility, except for the initialize family.
  #: (value, word, ptr, word, word, ptr, value) -> value
  def zr_define_method_public(klass, mid, fn, arity, kind, meta, cref)
    zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, Machine.value(QNIL)))
  end

  #: (value, word, ptr, word, word, ptr, value, word) -> value
  def zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, vis)
    # Under `1.instance_eval`, no singleton class can take the method.
    if cref != QNIL && RCref[cref].eval == EVAL_NO_DEF
      Machine.store64(zr_direct_pending(), 0, 0)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
    end
    frozen = zr_class_modify_check(klass)
    if frozen == QUNDEF
      Machine.store64(zr_direct_pending(), 0, 0)
      return frozen
    end
    klass = zr_origin(klass)
    if meta == 0
      meta = zr_xmalloc(FrameMeta.size)
      FrameMeta[meta].file = 0
      FrameMeta[meta].file_len = 0
      FrameMeta[meta].kind = KIND_BUILTIN
      FrameMeta[meta].line = 0
      FrameMeta[meta].parent = 0
      FrameMeta[meta].arity = arity
      FrameMeta[meta].params = 0
      FrameMeta[meta].fn = 0
      FrameMeta[meta].box = Machine.value(QNIL)
      FrameMeta[meta].ruby = 0
      FrameMeta[meta].node = 0
      FrameMeta[meta].cover = 0
    elsif Machine.word(FrameMeta[meta].owner) != 0 && FrameMeta[meta].owner != klass
      # The same def run under a different class (a class body in a block
      # that runs two times) gets its own meta, so each keeps its owner.
      copy = zr_xmalloc(FrameMeta.size)
      zr_memcpy(copy, meta, FrameMeta.size)
      meta = copy
    end
    FrameMeta[meta].name = mid
    FrameMeta[meta].owner = klass
    modfn = cref != QNIL && RCref[cref].modfn != 0
    core = !zr_program_started_p() || zr_internal_meta_p(meta) ? ROW_CORE : 0
    if modfn
      single = zr_singleton_class(klass)
      owned = zr_meta_owned(meta, single)
      zr_method_add_row(single, mid, fn, arity, kind, owned, cref, VIS_PUBLIC | core)
      zr_coverage_method_claim(single, mid, owned)
    end
    zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, vis | core)
    zr_coverage_method_claim(klass, mid, meta)
    # The entries have their direct entry (zr_define_method_direct). The
    # hooks run with none pending.
    Machine.store64(zr_direct_pending(), 0, 0)
    # Under `module_function`, one def makes two methods, and ruby reports
    # both.
    r = zr_method_added(klass, mid)
    return r if r == QUNDEF || !modfn

    zr_method_added(zr_singleton_class(klass), mid)
  end

  # `meta` as the method of `owner` shows it: the module function's copy
  # on the singleton class labels its frames `Mod.name`, and the private
  # instance method labels them `Mod#name`.
  #: (ptr, value) -> ptr
  def zr_meta_owned(meta, owner)
    if meta == 0 || FrameMeta[meta].owner == owner
      return meta
    end
    copy = zr_xmalloc(FrameMeta.size)
    zr_memcpy(copy, meta, FrameMeta.size)
    FrameMeta[copy].owner = owner
    copy
  end

  # The visibility that a definition under `cref` gets: the body's current
  # one, private under `module_function`, and always private for
  # `initialize` and related methods.
  #: (word, value) -> word
  def zr_definition_vis(mid, cref)
    if mid == Machine.id(:initialize) || mid == Machine.id(:initialize_copy) || mid == Machine.id(:initialize_clone) ||
       mid == Machine.id(:initialize_dup) || mid == Machine.id(:respond_to_missing?)
      return VIS_PRIVATE
    end
    if cref == QNIL
      return VIS_PUBLIC
    end
    if RCref[cref].modfn != 0
      return VIS_PRIVATE
    end
    RCref[cref].vis
  end

  # The visibility and the `module_function` copy that a `def` gets under
  # `cref`, for the tree-walking interpreter. It defines a method as
  # `Module#define_method` does, then applies the body's rules, which only
  # the cref knows. 0 public, 1 private, 2 protected.
  #: (value, value) -> value
  def zr_definition_vis_m(name, cref)
    zr_fix(zr_definition_vis(zr_sym2id(name), cref))
  end

  # Whether a `def` under `cref` also copies itself to the singleton
  # class, as `module_function` requires.
  #: (value) -> value
  def zr_cref_modfn_p(cref)
    zr_bool(cref != QNIL && RCref[cref].modfn != 0)
  end

  # A method whose body is the Proc `body`, kept in the entry's cref slot.
  # `cref` gives the visibility.
  #: (value, word, ptr, value, value) -> value
  def zr_define_bmethod(klass, mid, meta, body, cref)
    klass = zr_origin(klass)
    FrameMeta[meta].name = mid
    FrameMeta[meta].owner = klass
    modfn = cref != QNIL && RCref[cref].modfn != 0
    # `meta` is the frame of the call, which a backtrace shows. Coverage
    # shows the block, so the entry gets its coverage from the Proc's own
    # meta. A Proc from a Symbol or a Method has none, as CRuby's
    # rb_proc_get_iseq returns nothing for it.
    block_meta = RProc[body].meta
    # The entry's `fn` is the block's twin, if it has one (FrameMeta).
    twin = 0
    if block_meta != 0 && RProc[body].fn == FrameMeta[block_meta].fn
      twin = FrameMeta[block_meta].twin
    end
    if modfn
      single = zr_singleton_class(klass)
      zr_method_add_vis(single, mid, twin, 0 - 1, KIND_BMETHOD, meta, body, VIS_PUBLIC)
      zr_coverage_method_claim(single, mid, block_meta)
    end
    zr_method_add_vis(klass, mid, twin, 0 - 1, KIND_BMETHOD, meta, body, zr_definition_vis(mid, cref))
    zr_coverage_method_claim(klass, mid, block_meta)
    r = zr_method_added(klass, mid)
    return r if r == QUNDEF || !modfn

    zr_method_added(zr_singleton_class(klass), mid)
  end

  # Calls the `method_added` hook, or `singleton_method_added` on the
  # object that a singleton class is attached to. Nothing until the hooks
  # exist.
  #: (value, word) -> value
  def zr_method_added(klass, mid)
    if zr_type(klass) == T_ICLASS
      klass = RClass[klass].attached
    end
    if zr_singleton_p(klass)
      recv = RClass[klass].attached
      hook = Machine.id(:singleton_method_added)
    else
      recv = klass
      hook = Machine.id(:method_added)
    end
    if zr_find_method(zr_class_of(recv), hook) == 0
      return Machine.value(QNIL)
    end
    zr_hook(recv, hook, zr_sym(mid))
  end

  #: (value, word, ptr, word, word, ptr, value) -> void
  def zr_method_add(klass, mid, fn, arity, kind, meta, cref)
    zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
  end

  # Adds the entry to the table with the meta unchanged (an alias keeps the
  # original's name).
  #: (value, word, ptr, word, word, ptr, value, word) -> void
  def zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
    zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, zr_program_started_p() ? vis : vis | ROW_CORE)
  end

  # Whether `meta` is a method from the runtime's own Ruby, whose frames
  # show no file. A library such as zlib is also part of the core library,
  # although it loads after the program starts.
  #: (ptr) -> bool
  def zr_internal_meta_p(meta)
    meta != 0 && FrameMeta[meta].file_len == 0 && (FrameMeta[meta].kind == KIND_BUILTIN || FrameMeta[meta].kind == KIND_HIDDEN)
  end

  # The same, with ROW_CORE in `vis` when the core library defines the
  # entry. The core library's sends find that entry even after a program
  # overwrites it.
  ROW_CORE = 256

  #: (value, word, ptr, word, word, ptr, value, word) -> void
  def zr_method_add_row(klass, mid, fn, arity, kind, meta, cref, vis)
    core = (vis & ROW_CORE) != 0
    vis = vis & (ROW_CORE - 1)
    owner = klass
    klass = zr_origin(klass)
    if !core && zr_program_started_p() && !zr_hidden_now()
      zr_warn_dangerous(owner, mid, kind)
    end
    # Only a small number of names have a gate, so get the bit before
    # checking the ancestor list for a redefinition. A builtin entry that
    # the runtime writes at boot is in place of the kernel's own: `freeze`
    # on String is Kernel's function, which the fast path replaces.
    #
    # A def in `refine C` refines C: the gate of its name on C closes as
    # for a definition on C, at the definition and not at the `using`. This
    # is sooner than necessary, and for each site, but it lets a site under
    # `using` keep an operator's fast path.
    over = klass
    if zr_type(klass) == T_MODULE && ClassExt[RClass[klass].ext].refined != QNIL
      over = ClassExt[RClass[klass].ext].refined
    end
    bit = zr_gate_bit(over, mid)
    booting = kind == KIND_BUILTIN && !zr_program_started_p()
    if bit != 0 && !booting && zr_find_method(over, mid) != 0
      Machine.gates_set(Machine.gates | bit)
    end
    # The type checks have no class of their own: after program start, a
    # definition of the name on any class closes the gate.
    if zr_program_started_p()
      if mid == Machine.id(:is_a?) || mid == Machine.id(:kind_of?)
        Machine.gates_set(Machine.gates | GATE_IS_A)
      elsif mid == Machine.id(:instance_of?)
        Machine.gates_set(Machine.gates | GATE_INSTANCE_OF)
      elsif mid == Machine.id(:nil?)
        Machine.gates_set(Machine.gates | GATE_NIL_P)
      end
    end
    zr_methods_changed()
    ext = RClass[klass].ext
    # A redefinition uses the name's existing entry, as ruby does:
    # `instance_methods` shows it at the position of the first definition,
    # and a later `remove_method` leaves nothing.
    e = zr_find_method_at(klass, mid)
    if e != 0 && !core
      zr_warn_operator(owner, mid, e)
    end
    if !core
      zr_warn_redefined(owner, ext, mid, e, fn, kind, meta, cref)
    end
    if !core
      zr_save_core_row(ext, e)
    end
    # A method that a file loads onto a class of the program while the
    # eval support loads that file stays out of the program's sight, as a
    # constant does, until the program requires the file itself
    # (zr_feature_reveal). A method that eval support defines for the
    # program, as an FFI attach does, is the program's.
    conceal = !core && zr_program_started_p() && zr_loading_hidden() && (RBasic[klass].flags & FL_CONCEALED) == 0
    conceal = conceal && (e == 0 || MEntry[e].concealed != 0)
    if e == 0
      n = ClassExt[ext].mlen
      if n == ClassExt[ext].mcap
        cap = n * 2
        if cap < 8
          cap = 8
        end
        tab = zr_xmalloc(cap * MEntry.size)
        old = ClassExt[ext].mtab
        if old != 0
          zr_memcpy(tab, old, n * MEntry.size)
          zr_xfree(old)
        end
        ClassExt[ext].mtab = tab
        ClassExt[ext].mcap = cap
      end
      e = ClassExt[ext].mtab + (n * MEntry.size)
      ClassExt[ext].mlen = n + 1
      MEntry[e].mid = mid
      zr_method_index_add(ext, n)
    end
    MEntry[e].mid = mid
    MEntry[e].fn = fn
    MEntry[e].arity = arity
    MEntry[e].kind = kind
    MEntry[e].meta = meta
    MEntry[e].cref = cref
    zr_write_barrier(klass, cref)
    MEntry[e].vis = vis
    MEntry[e].orig = mid
    MEntry[e].from = Machine.value(QNIL)
    MEntry[e].core = core ? 1 : 0
    MEntry[e].cover = 0
    MEntry[e].direct = Machine.ptr(Machine.load64(zr_direct_pending(), 0))
    MEntry[e].ivar.index = 0
    MEntry[e].concealed = conceal ? 1 : 0
    if conceal
      zr_hidden_defined_method(klass, mid)
    end
    zr_gates_recheck(mid)
  end

  # Whether `mid` on `klass` is one of CRuby's basic operators, which the
  # interpreter and the JITs run inline while the core's entry is in place
  # (vm_init_redefined_flag at 4.0.7).
  #: (value, word) -> bool
  def zr_basic_operator_p(klass, mid)
    int = klass == zr_global(G_INTEGER)
    flo = klass == zr_global(G_FLOAT)
    str = klass == zr_global(G_STRING)
    ary = klass == zr_global(G_ARRAY)
    hsh = klass == zr_global(G_HASH)
    sym = klass == zr_global(G_SYMBOL)
    if mid == Machine.id(:+)
      return int || flo || str || ary
    elsif mid == Machine.id(:-) || mid == Machine.id(:*) || mid == Machine.id(:/) || mid == Machine.id(:%) ||
          mid == Machine.id(:<) || mid == Machine.id(:<=) || mid == Machine.id(:>) || mid == Machine.id(:>=)
      return int || flo
    elsif mid == Machine.id(:==)
      return int || flo || str || sym
    elsif mid == Machine.id(:===)
      return int || flo || sym || str || klass == zr_global(G_NIL) || klass == zr_global(G_TRUE) || klass == zr_global(G_FALSE)
    elsif mid == Machine.id(:<<)
      return str || ary
    elsif mid == Machine.id(:>>) || mid == Machine.id(:&) || mid == Machine.id(:|)
      return int
    elsif mid == Machine.id(:[])
      return ary || hsh || int
    elsif mid == Machine.id(:[]=)
      return ary || hsh
    elsif mid == Machine.id(:length) || mid == Machine.id(:size) || mid == Machine.id(:empty?)
      return ary || str || hsh
    elsif mid == Machine.id(:succ)
      return int || str
    elsif mid == Machine.id(:=~)
      return klass == zr_global(G_REGEXP) || str
    elsif mid == Machine.id(:freeze)
      return str || ary || hsh
    elsif mid == Machine.id(:-@)
      return str
    elsif mid == Machine.id(:max) || mid == Machine.id(:min) || mid == Machine.id(:hash) || mid == Machine.id(:include?)
      return ary
    elsif mid == Machine.id(:call)
      return klass == zr_global(G_PROC)
    elsif mid == Machine.id(:nil?)
      return klass == zr_global(G_NIL)
    elsif mid == Machine.id(:<=>)
      return int || flo || str
    elsif mid == Machine.id(:default)
      return hsh
    end
    false
  end

  # `Redefining 'C#m' disables interpreter and JIT optimizations`, under
  # `Warning[:performance]`, where rb_vm_check_redefinition_opt_method
  # warns. Entry `e` of `klass` is the core's own, under its own name, for
  # a basic operator, and a program is about to overwrite it, remove it,
  # undefine it or put a prepended entry before it. The core's entry goes
  # with the first of these, so a second one gives no warning.
  #: (value, word, ptr) -> void
  def zr_warn_operator(klass, mid, e)
    if !zr_program_started_p() || MEntry[e].core == 0 || MEntry[e].orig != mid || !zr_basic_operator_p(klass, mid)
      return
    end
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(klass))
    Machine.store64(slot, 8, Machine.word(zr_sym(mid)))
    zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:operator_redefined), 2, slot)
  end

  # After a prepend into `klass`: warns for each basic operator whose core
  # entry is no longer first in the ancestor list, as
  # rb_vm_check_redefinition_by_prepend walks the origin's table.
  #: (value, word) -> void
  def zr_warn_prepended_operator(klass, mid)
    e = zr_find_method_at(zr_origin(klass), mid)
    if e != 0 && zr_find_method(klass, mid) != e
      zr_warn_operator(klass, mid, e)
    end
  end

  #: (value) -> value
  def zr_warn_prepended_operators(klass)
    zr_warn_prepended_operator(klass, Machine.id(:+))
    zr_warn_prepended_operator(klass, Machine.id(:-))
    zr_warn_prepended_operator(klass, Machine.id(:*))
    zr_warn_prepended_operator(klass, Machine.id(:/))
    zr_warn_prepended_operator(klass, Machine.id(:%))
    zr_warn_prepended_operator(klass, Machine.id(:==))
    zr_warn_prepended_operator(klass, Machine.id(:===))
    zr_warn_prepended_operator(klass, Machine.id(:<))
    zr_warn_prepended_operator(klass, Machine.id(:<=))
    zr_warn_prepended_operator(klass, Machine.id(:>))
    zr_warn_prepended_operator(klass, Machine.id(:>=))
    zr_warn_prepended_operator(klass, Machine.id(:<<))
    zr_warn_prepended_operator(klass, Machine.id(:>>))
    zr_warn_prepended_operator(klass, Machine.id(:[]))
    zr_warn_prepended_operator(klass, Machine.id(:[]=))
    zr_warn_prepended_operator(klass, Machine.id(:length))
    zr_warn_prepended_operator(klass, Machine.id(:size))
    zr_warn_prepended_operator(klass, Machine.id(:empty?))
    zr_warn_prepended_operator(klass, Machine.id(:succ))
    zr_warn_prepended_operator(klass, Machine.id(:=~))
    zr_warn_prepended_operator(klass, Machine.id(:freeze))
    zr_warn_prepended_operator(klass, Machine.id(:-@))
    zr_warn_prepended_operator(klass, Machine.id(:max))
    zr_warn_prepended_operator(klass, Machine.id(:min))
    zr_warn_prepended_operator(klass, Machine.id(:hash))
    zr_warn_prepended_operator(klass, Machine.id(:call))
    zr_warn_prepended_operator(klass, Machine.id(:&))
    zr_warn_prepended_operator(klass, Machine.id(:|))
    zr_warn_prepended_operator(klass, Machine.id(:nil?))
    zr_warn_prepended_operator(klass, Machine.id(:<=>))
    zr_warn_prepended_operator(klass, Machine.id(:default))
    zr_warn_prepended_operator(klass, Machine.id(:include?))
    Machine.value(QNIL)
  end

  # `method redefined; discarding old m`, where rb_method_entry_make
  # warns: under `$VERBOSE` true, for a definition over an entry that is
  # not an undef, not an alias, not a copy that a visibility call made of
  # an ancestor's method, and not aliased. A method written in Ruby tells
  # where it was defined. The runtime's own definitions give no warning.
  #: (value, ptr, word, ptr, ptr, word, ptr, value) -> void
  def zr_warn_redefined(owner, ext, mid, e, fn, kind, meta, cref)
    if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE || !zr_program_started_p() || Task[zr_task()].top == 0 || zr_hidden_now()
      return
    end
    if kind == KIND_UNDEF || (zr_internal_meta_p(meta) && !zr_word_entry_p(kind))
      return
    end
    # A name that ruby defines in its core: the table from ruby decides,
    # whatever entry the runtime keeps for it (a builtin, an alias of
    # another name, or one on an ancestor). Only an alias that the program
    # made keeps it quiet, as it does in ruby. A core method that the
    # program removed is no longer there to redefine.
    if e == 0 && zr_saved_row(ext, mid) != 0
      return
    end
    if e == 0 || (MEntry[e].core & 1) != 0
      known = true
      if e == 0 || (MEntry[e].kind != KIND_UNDEF && !zr_entry_hidden_p(e) && !zr_program_aliased_p(ext, e, mid))
        known = zr_warn_core_redefined(owner, mid)
      end
      if known || e == 0
        return
      end
    end
    if MEntry[e].kind == KIND_UNDEF || MEntry[e].orig != mid || MEntry[e].from != QNIL || zr_entry_hidden_p(e)
      return
    end
    # The same definition again, as from `alias_method :m, :m` or a second
    # `module_function :m`: the same body, or the same Proc.
    body = Machine.ptr(Machine.load64(zr_direct_pending(), 0))
    if body == 0
      body = fn
    end
    if MEntry[e].kind == kind && (kind == KIND_BMETHOD ? MEntry[e].cref == cref : zr_entry_body(e) == body && !zr_word_entry_p(kind))
      return
    end
    if MEntry[e].fn == 0 && MEntry[e].kind != KIND_BMETHOD && !zr_word_entry_p(MEntry[e].kind)
      return
    end
    if zr_program_aliased_p(ext, e, mid)
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("method redefined; discarding old "), 33)
    zr_buf_sym(b, mid)
    old = MEntry[e].meta
    if (MEntry[e].kind == KIND_DEF || MEntry[e].kind == KIND_BMETHOD) && old != 0 && FrameMeta[old].file_len > 0
      zr_buf_byte(b, 10)
      zr_buf_push(b, FrameMeta[old].file, FrameMeta[old].file_len)
      zr_buf_byte(b, 58)
      zr_buf_long(b, FrameMeta[old].line)
      zr_buf_push(b, Machine.bytes(": warning: previous definition of "), 34)
      zr_buf_sym(b, mid)
      zr_buf_push(b, Machine.bytes(" was here"), 9)
    end
    zr_warn_here(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
  end

  # Whether `ext` holds an alias of `mid` other than the entry `e`: an
  # aliased method gives no warning when it is redefined. The core's own
  # aliases do not count, because ruby's core has other ones.
  #: (ptr, ptr, word) -> bool
  def zr_program_aliased_p(ext, e, mid)
    i = 0
    while i < ClassExt[ext].mlen
      row = ClassExt[ext].mtab + (i * MEntry.size)
      if row != e && MEntry[row].orig == mid && MEntry[row].mid != mid && MEntry[row].kind != KIND_UNDEF && (MEntry[row].core & 1) == 0
        return true
      end
      i += 1
    end
    false
  end

  # The warning for a method of the core that a program redefines, as
  # ruby 4.0.7 gives it: Warning.redefinition reads the generated table
  # (lib/zr/runtime/core/redefinitions.rb), which knows the methods that ruby
  # does not warn for and the <internal:*> line of each def.
  #: (value, word) -> bool
  def zr_warn_core_redefined(owner, mid)
    slot = Machine.slot(16)
    Machine.store64(slot, 0, Machine.word(owner))
    Machine.store64(slot, 8, Machine.word(zr_sym(mid)))
    where = zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:redefinition), 2, slot)
    if where == QTRUE
      return false
    end
    if where == QFALSE || where == QUNDEF
      return true
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("method redefined; discarding old "), 33)
    zr_buf_sym(b, mid)
    if where != QNIL
      zr_buf_byte(b, 10)
      zr_buf_push(b, RString[where].ptr, RString[where].len)
      zr_buf_push(b, Machine.bytes(": warning: previous definition of "), 34)
      zr_buf_sym(b, mid)
      zr_buf_push(b, Machine.bytes(" was here"), 9)
    end
    zr_warn_here(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
    true
  end

  # rb_method_entry_make's warnings about names that ruby itself depends
  # on, whatever $VERBOSE says unless it is nil: four names on Object, and
  # a def of object_id or __send__ over one that exists.
  #: (value, word, word) -> void
  def zr_warn_dangerous(owner, mid, kind)
    # An extension's Ruby part is C in ruby, whose definitions do not warn.
    if zr_loading_internal()
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    object = mid == Machine.id(:initialize) || mid == Machine.id(:respond_to_missing?)
    object = object || mid == Machine.id(:method_missing) || mid == Machine.id(:respond_to?)
    if owner == zr_global(G_OBJECT) && object
      zr_buf_push(b, Machine.bytes("redefining Object#"), 18)
      zr_buf_sym(b, mid)
      zr_buf_push(b, Machine.bytes(" may cause infinite loop"), 24)
      zr_warn_here(Buf[b].ptr, Buf[b].len)
    else
      if kind == KIND_UNDEF && (mid == Machine.id(:object_id) || mid == Machine.id(:__send__) || mid == Machine.id(:initialize))
        # rb_undef warns for the names that ruby itself depends on, then
        # adds its undef entry as any new entry is added.
        zr_buf_push(b, Machine.bytes("undefining '"), 12)
        zr_buf_sym(b, mid)
        zr_buf_push(b, Machine.bytes("' may cause serious problems"), 28)
        zr_warn_here(Buf[b].ptr, Buf[b].len)
        Buf[b].len = 0
      end
      if (mid == Machine.id(:object_id) || mid == Machine.id(:__send__)) && zr_find_method(owner, mid) != 0
        # Any new entry over one of them warns: a def, a reader, a
        # define_method, a Struct member, an alias or an undef.
        zr_buf_push(b, Machine.bytes("redefining '"), 12)
        zr_buf_sym(b, mid)
        zr_buf_push(b, Machine.bytes("' may cause serious problems"), 28)
        zr_warn_here(Buf[b].ptr, Buf[b].len)
      end
    end
    zr_buf_free(b)
  end

  # Whether the program has started: all of the core library's own
  # definitions are written.
  #: () -> bool
  def zr_program_started_p
    Machine.load64(Machine.static(:program_started, 8), 0) != 0
  end

  # Marks that the runtime's own definitions are all written. All later
  # definitions are the program's, starting with the gem prelude's
  # libraries.
  #: () -> void
  def zr_runtime_written
    Machine.store64(Machine.static(:program_started, 8), 0, 1)
  end

  # Saves entry `e` of `ext`, a core library entry that a program is about
  # to overwrite or remove, for the core library's own sends. It saves
  # nothing for other entries, and saves each name only one time.
  #: (ptr, ptr) -> void
  def zr_save_core_row(ext, e)
    if e == 0 || MEntry[e].core == 0 || !zr_program_started_p() || zr_saved_row(ext, MEntry[e].mid) != 0
      return
    end
    n = ClassExt[ext].slen
    tab = zr_xmalloc((n + 1) * MEntry.size)
    if n > 0
      zr_memcpy(tab, ClassExt[ext].saved, n * MEntry.size)
      zr_xfree(ClassExt[ext].saved)
    end
    zr_memcpy(tab + (n * MEntry.size), e, MEntry.size)
    ClassExt[ext].saved = tab
    ClassExt[ext].slen = n + 1
  end

  #: (ptr, word) -> ptr
  def zr_saved_row(ext, mid)
    i = 0
    while i < ClassExt[ext].slen
      e = ClassExt[ext].saved + (i * MEntry.size)
      if MEntry[e].mid == mid
        return e
      end
      i += 1
    end
    0
  end

  # Whether the core library's own sends to an instance of `klass` find
  # the core library's methods: true for a class that the runtime made
  # before the program started. A class's singleton class counts as its
  # attached class, so a program's subclass keeps its own class methods.
  # Any other singleton class counts as the class after it.
  #: (value) -> bool
  def zr_core_class_p(klass)
    if !zr_program_started_p()
      return false
    end
    while klass != QNIL && (RBasic[klass].flags & FL_SINGLETON) != 0
      attached = RClass[klass].attached
      if !zr_special_p(attached) && (zr_type(attached) == T_CLASS || zr_type(attached) == T_MODULE)
        klass = attached
      else
        klass = RClass[klass].superclass
      end
    end
    klass != QNIL && ClassExt[RClass[klass].ext].serial <= Machine.load64(Machine.static(:master_serial, 8), 0)
  end

  # The entry for `mid` on `klass` that a core library send finds: the
  # core library's own entry, even if a program overwrote it, removed it,
  # or put a module before it. This matches CRuby, where a call in C gets a
  # C function, not a method that the program defines. Returns 0 when the
  # core library defines no such method in the ancestor list; then the send
  # finds what any send finds.
  #: (value, word) -> ptr
  def zr_search_core_method(klass, mid)
    k = klass
    while k != QNIL
      ext = RClass[k].ext
      e = zr_saved_row(ext, mid)
      if e == 0
        e = zr_find_method_at(k, mid)
        if e != 0 && MEntry[e].core == 0
          e = 0
        end
      end
      if e != 0
        if MEntry[e].kind == KIND_UNDEF
          return 0
        end
        Task[zr_task()].found = k
        return e
      end
      k = RClass[k].superclass
    end
    0
  end

  # The same, from the method cache under a separate key.
  #: (value, word) -> ptr
  def zr_find_core_method(klass, mid)
    mode = Machine.load64(Machine.static(:mcache_mode, 8), 0)
    if mode == MCACHE_OFF
      return zr_search_core_method(klass, mid)
    end
    key = mid | CORE_KEY
    h = ((Machine.word(klass) / CELL_MIN) ^ Machine.mul_wrap(key, 31)) & (MCACHE_ROWS - 1)
    row = Machine.static(:mcache, MCACHE_ROWS * MCache.size) + (h * MCache.size)
    stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
    if MCache[row].stamp == stamp && MCache[row].klass == klass && MCache[row].mid == key
      e = MCache[row].entry
      if e != 0
        Task[zr_task()].found = MCache[row].found
      end
      if mode == MCACHE_VERIFY && e != zr_search_core_method(klass, mid)
        zr_bug(Machine.bytes("the method cache answered what the core chain does not\n"), 55)
      end
      return e
    end
    e = zr_search_core_method(klass, mid)
    MCache[row].klass = klass
    MCache[row].mid = key
    MCache[row].entry = e
    MCache[row].found = e == 0 ? Machine.value(QNIL) : Task[zr_task()].found
    MCache[row].stamp = stamp
    MCache[row].refine = Machine.value(QNIL)
    e
  end

  # A method cache entry for a core library send uses the name with this
  # bit as its key. No symbol id has this bit.
  CORE_KEY = 1 << 62

  # Adds entry `e` again on `klass` as `mid`. It keeps the name of the
  # first definition and, when `zr_find_method` just found `e` (`found`),
  # the ancestor list node where it was.
  #: (value, word, ptr, ptr, word, bool) -> void
  def zr_method_copy(klass, mid, e, meta, vis, found)
    orig = MEntry[e].orig
    from = MEntry[e].from
    if found && from == QNIL
      from = Task[zr_task()].found
    end
    cover = MEntry[e].cover
    direct = MEntry[e].direct
    zr_method_add_vis(klass, mid, MEntry[e].fn, MEntry[e].arity, MEntry[e].kind, meta, MEntry[e].cref, vis)
    e = zr_find_method_at(zr_origin(klass), mid)
    MEntry[e].orig = orig
    MEntry[e].from = from
    # An alias or a visibility copy of a def with a direct entry keeps it.
    MEntry[e].direct = direct
    zr_write_barrier(klass, from)
    # An alias counts for coverage where its original counts, as
    # rb_resolve_me_location does for the :call event.
    MEntry[e].cover = cover
  end

  # `private`, `public`, `protected` and `module_function` in a class
  # body. With no names, they set the visibility of later defs through
  # the caller's cref. With names, they change those methods on `klass`.
  #: (value, word, ptr, value, word, word) -> value
  def zr_set_visibility(klass, argc, argv, blk, vis, modfn)
    if argc == 0
      cref = Frame[Frame[Task[zr_task()].top].prev].cref
      if cref == QNIL
        zr_bug(Machine.bytes("a visibility verb outside a class body is not implemented yet\n"), 62)
      end
      if modfn != 0
        RCref[cref].modfn = 1
      else
        RCref[cref].vis = vis
        RCref[cref].modfn = 0
      end
      return Machine.value(QNIL)
    end
    i = 0
    while i < argc
      name = Machine.value(Machine.load64(argv + (i * 8), 0))
      if !zr_special_p(name) && zr_type(name) == T_ARRAY
        r = zr_set_visibility(klass, RArray[name].len, RArray[name].ptr, blk, vis, modfn)
        return r if r == QUNDEF
      else
        slot = Machine.slot(8)
        r = zr_name_id(name, slot)
        return r if r == QUNDEF
        r = zr_set_method_visibility(klass, Machine.load64(slot, 0), vis, modfn)
        return r if r == QUNDEF
      end
      i += 1
    end
    if argc == 1
      return Machine.value(Machine.load64(argv, 0))
    end
    zr_ary_of(argc, argv)
  end

  #: (value, word, word, word) -> value
  def zr_set_method_visibility(klass, mid, vis, modfn)
    frozen = zr_class_modify_check(klass)
    return frozen if frozen == QUNDEF
    e = zr_find_method(klass, mid)
    if e == 0 && !zr_special_p(klass) && zr_type(klass) == T_MODULE
      # A module looks in Object too, as rb_export_method does:
      # `module Kernel; public :m; end` for an m that Object defines.
      e = zr_find_method(zr_global(G_OBJECT), mid)
    end
    if e == 0
      # With the name and the receiver, which did_you_mean reads.
      return zr_undefined_method(klass, mid, VIS_PUBLIC)
    end
    if modfn != 0
      single = zr_singleton_class(klass)
      zr_method_copy(single, mid, e, zr_meta_owned(MEntry[e].meta, single), VIS_PUBLIC, false)
      vis = VIS_PRIVATE
    end
    # If the method is on an ancestor, the call makes an entry here, and a
    # new entry is a definition, so it calls the hook. A change to an entry
    # that this class already has calls no hook.
    copied = zr_find_method_at(zr_origin(klass), mid) != e
    if copied
      zr_method_copy(zr_origin(klass), mid, e, MEntry[e].meta, vis, true)
    else
      MEntry[e].vis = vis
      zr_methods_changed()
      zr_gates_recheck(mid)
    end
    # The hooks run last: a hook can define a method, which moves the table
    # that contains the entry.
    if modfn != 0
      r = zr_method_added(zr_singleton_class(klass), mid)
      return r if r == QUNDEF
    end
    if copied
      r = zr_method_added(zr_origin(klass), mid)
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_private(recv, argc, argv, cref, blk)
    zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public(recv, argc, argv, cref, blk)
    zr_set_visibility(recv, argc, argv, blk, VIS_PUBLIC, 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_protected(recv, argc, argv, cref, blk)
    zr_set_visibility(recv, argc, argv, blk, VIS_PROTECTED, 0)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_module_function(recv, argc, argv, cref, blk)
    zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 1)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_private_class_method(recv, argc, argv, cref, blk)
    r = zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PRIVATE, 0)
    return r if r == QUNDEF
    # rb_mod_private_method returns the receiver, whatever it was given.
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public_class_method(recv, argc, argv, cref, blk)
    r = zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PUBLIC, 0)
    return r if r == QUNDEF
    recv
  end

  # Whether `e` is a helper that the core library keeps for itself (a def
  # marked `Primitive.attr! :hidden`), where CRuby has no method. No list
  # shows it, and `respond_to?` and `method_defined?` return false. A
  # method from `define_method` has its caller's meta, so only a compiled
  # def or a builtin counts. So does a method that the eval support defined
  # on a class of the program, except to the eval support itself.
  #: (ptr) -> bool
  def zr_entry_hidden_p(e)
    if MEntry[e].concealed != 0 && !zr_hidden_now()
      return true
    end
    (MEntry[e].kind == KIND_DEF || MEntry[e].kind == KIND_BUILTIN) && MEntry[e].meta != 0 && FrameMeta[MEntry[e].meta].kind == KIND_HIDDEN
  end

  # Adds the names in one level's table to `out`, filtered by `vis` (a
  # visibility, or -1 for all except private). A name found at an earlier
  # level is in `seen` and was decided there, also an undef or a hidden
  # helper.
  #: (value, value, value, word) -> void
  def zr_level_method_names(level, out, seen, vis)
    ext = RClass[level].ext
    i = 0
    while i < ClassExt[ext].mlen
      e = ClassExt[ext].mtab + (i * MEntry.size)
      name = zr_sym(MEntry[e].mid)
      if zr_ary_index_of(seen, name) < 0
        zr_ary_push(seen, name)
        e = zr_find_method_at(level, MEntry[e].mid)
        if MEntry[e].kind != KIND_UNDEF && !zr_entry_hidden_p(e) && (vis < 0 ? MEntry[e].vis != VIS_PRIVATE : MEntry[e].vis == vis)
          zr_ary_push(out, name)
        end
      end
      i += 1
    end
  end

  # `undefined_instance_methods`: the names that this module's own table
  # undefines, where a call stops at the module.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_undefined_instance_methods(recv, argc, argv, cref, blk)
    ext = RClass[zr_origin(recv)].ext
    out = zr_ary_new(4)
    i = 0
    while i < ClassExt[ext].mlen
      e = ClassExt[ext].mtab + (i * MEntry.size)
      if MEntry[e].kind == KIND_UNDEF && zr_ary_index_of(out, zr_sym(MEntry[e].mid)) < 0
        zr_ary_push(out, zr_sym(MEntry[e].mid))
      end
      i += 1
    end
    out
  end

  # `instance_methods` and the three by visibility, on a module (`all`
  # includes the ancestors) or, for `methods` on an object, on its
  # ancestor list: the singleton class and its extended modules come first.
  #: (value, word, word, bool) -> value
  def zr_method_names(klass, all, vis, object)
    out = zr_ary_new(8)
    seen = zr_ary_new(8)
    k = all == 0 ? zr_origin(klass) : klass
    if object
      while k != QNIL && (zr_singleton_p(k) || zr_type(k) == T_ICLASS)
        zr_level_method_names(k, out, seen, vis)
        k = RClass[k].superclass
      end
    end
    while k != QNIL
      zr_level_method_names(k, out, seen, vis)
      if all == 0
        k = Machine.value(QNIL)
      else
        k = RClass[k].superclass
      end
    end
    out
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_instance_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(recv, all ? 1 : 0, 0 - 1, false)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_public_instance_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(recv, all ? 1 : 0, VIS_PUBLIC, false)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_private_instance_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(recv, all ? 1 : 0, VIS_PRIVATE, false)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_protected_instance_methods(recv, argc, argv, cref, blk)
    all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
    zr_method_names(recv, all ? 1 : 0, VIS_PROTECTED, false)
  end

  #: (value, word, ptr, word) -> void
  def zr_builtin(klass, mid, fn, arity)
    zr_define_method(klass, mid, fn, arity, KIND_BUILTIN, 0, Machine.value(QNIL))
  end

  # `rb_f_notimplement`: the entry for a call that this platform does not
  # have. It is listed, reflects as taking no arguments, and `respond_to?`
  # returns false. A call raises NotImplementedError with the function name.
  #: (value, word, ptr, value, value) -> value
  def zr_f_notimplement(recv, argc, argv, cref, blk)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_sym(b, zr_frame_mid(Task[zr_task()].top))
    zr_buf_push(b, Machine.bytes("() function is unimplemented on this machine"), 44)
    zr_raise_buf(zr_core_class(Machine.id(:NotImplementedError)), b)
  end

  # The core's way to give `klass` such an entry under `name`, a Symbol.
  #: (value, value) -> value
  def zr_define_notimplement(klass, name)
    zr_builtin(klass, zr_sym2id(name), Machine.addr(:zr_f_notimplement), 0 - 1)
    Machine.value(QNIL)
  end

  # A private builtin, as Kernel's `puts` and `raise` are.
  #: (value, word, ptr, word) -> void
  def zr_builtin_private(klass, mid, fn, arity)
    zr_builtin(klass, mid, fn, arity)
    MEntry[zr_find_method_at(zr_origin(klass), mid)].vis = VIS_PRIVATE
    zr_methods_changed()
  end

  # A private builtin that the core library keeps for itself, as for a def
  # marked `Primitive.attr! :hidden`: no list shows it and no backtrace has
  # a frame for it.
  #: (value, word, ptr, word) -> void
  def zr_builtin_hidden(klass, mid, fn, arity)
    zr_builtin_private(klass, mid, fn, arity)
    FrameMeta[MEntry[zr_find_method_at(zr_origin(klass), mid)].meta].kind = KIND_HIDDEN
  end

  # Makes the method `mid` on `klass` visible. The eval support defined it,
  # and now the program required the file that defines it.
  #: (value, word) -> void
  def zr_method_reveal(klass, mid)
    e = zr_find_method_at(klass, mid)
    if e != 0 && MEntry[e].concealed != 0
      MEntry[e].concealed = 0
      zr_methods_changed()
    end
  end

  # The entry for `mid` on `klass` only, or 0; the last definition wins.
  # A method table of this length or more has a hash index of its names.
  # The index is built at the first lookup that needs it and dropped when
  # an entry is removed (const.rb does the same for constants). Kernel's
  # and Object's tables have hundreds of entries, and each ancestor walk
  # passes them. A shorter table is scanned. A name has one entry (a
  # redefinition uses its existing entry), so a bin contains that entry's
  # number plus one, or zero when empty.
  METHOD_INDEX_MIN = 16

  #: (ptr) -> void
  def zr_method_index_drop(ext)
    if ClassExt[ext].midx != 0
      zr_xfree(ClassExt[ext].midx)
      ClassExt[ext].midx = 0
    end
  end

  #: (ptr, word) -> void
  def zr_method_index_put(ext, row)
    mask = ClassExt[ext].mbins - 1
    h = Machine.mul_wrap(MEntry[ClassExt[ext].mtab + (row * MEntry.size)].mid, 2654435761) & mask
    while Machine.load64(ClassExt[ext].midx + (h * 8), 0) != 0
      h = (h + 1) & mask
    end
    Machine.store64(ClassExt[ext].midx + (h * 8), 0, row + 1)
  end

  # Puts each entry into a new index with at least four bins per entry.
  #: (ptr) -> void
  def zr_method_index_build(ext)
    zr_method_index_drop(ext)
    n = ClassExt[ext].mlen
    bins = 64
    while bins < n * 4
      bins = bins * 2
    end
    ClassExt[ext].midx = zr_xmalloc(bins * 8)
    Libc.memset(ClassExt[ext].midx, Machine.i32(0), bins * 8)
    ClassExt[ext].mbins = bins
    i = 0
    while i < n
      zr_method_index_put(ext, i)
      i += 1
    end
  end

  # Adds a new last entry to the index while the bins stay under half full.
  # Else it drops the index, and the next lookup builds a larger one.
  #: (ptr, word) -> void
  def zr_method_index_add(ext, row)
    if ClassExt[ext].midx == 0
      return
    end
    if (row + 1) * 2 > ClassExt[ext].mbins
      zr_method_index_drop(ext)
      return
    end
    zr_method_index_put(ext, row)
  end

  # The entry number of `mid` in the table plus one, or 0.
  #: (ptr, word) -> word
  def zr_method_index_find(ext, mid)
    if ClassExt[ext].midx == 0
      zr_method_index_build(ext)
    end
    mask = ClassExt[ext].mbins - 1
    h = Machine.mul_wrap(mid, 2654435761) & mask
    slot = Machine.load64(ClassExt[ext].midx + (h * 8), 0)
    while slot != 0
      if MEntry[ClassExt[ext].mtab + ((slot - 1) * MEntry.size)].mid == mid
        return slot
      end
      h = (h + 1) & mask
      slot = Machine.load64(ClassExt[ext].midx + (h * 8), 0)
    end
    0
  end

  #: (value, word) -> ptr
  def zr_find_method_at(klass, mid)
    ext = RClass[klass].ext
    n = ClassExt[ext].mlen
    tab = ClassExt[ext].mtab
    if n >= METHOD_INDEX_MIN
      slot = zr_method_index_find(ext, mid)
      return slot == 0 ? 0 : tab + ((slot - 1) * MEntry.size)
    end
    i = n - 1
    while i >= 0
      e = tab + (i * MEntry.size)
      if MEntry[e].mid == mid
        return e
      end
      i -= 1
    end
    0
  end

  # The result of an ancestor walk for one (class, name): the entry, the
  # ancestor list node that contained it, and the method stamp at that
  # time. `refine` is the activation list of the lookup (Task.refine), or
  # nil. A refined lookup has a separate entry, and never serves a plain
  # lookup. A `using` and a refinement's definition change the stamp.
  class MCache < Layout
    attr_accessor :klass #: value
    attr_accessor :mid #: word
    attr_accessor :entry #: ptr
    attr_accessor :found #: value
    attr_accessor :stamp #: word
    attr_accessor :refine #: value
  end

  MCACHE_ROWS = 2048
  # `ZR_MCACHE=0` does a walk for each send. `ZR_MCACHE=verify` gets both
  # results and stops if they differ, which finds a change to a method
  # table or an ancestor list that changes the stamp too late. Both also
  # apply to the call-site cache entries (cache.rb).
  MCACHE_OFF = 1
  MCACHE_VERIFY = 2

  #: () -> void
  def zr_mcache_init
    v = Libc.getenv(Machine.bytes("ZR_MCACHE\0"))
    if v != 0
      first = Machine.u8(Machine.load8(v, 0))
      if first == 48
        Machine.store64(Machine.static(:mcache_mode, 8), 0, MCACHE_OFF)
      elsif first == 118
        Machine.store64(Machine.static(:mcache_mode, 8), 0, MCACHE_VERIFY)
      end
    end
    # In both modes, a site's own check of its cache entry never hits: each
    # send goes through the kernel, which fills no entry or verifies each hit.
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) != 0
      Machine.store64(Machine.static(:site_stamp, 8), 0, 0 - 1)
    end
  end

  # Changes the method stamp. Called for a definition, an alias, an undef,
  # a visibility change, a module inserted into an ancestor list, a class
  # whose superclass is set, and a collection (a swept class's address can
  # go to a new class, and a cache entry identifies classes by address). A
  # constant lookup walks the same ancestor lists, so the constant stamp
  # changes too.
  #: () -> void
  def zr_methods_changed
    s = Machine.static(:mcache_stamp, 8)
    stamp = Machine.load64(s, 0) + 1
    Machine.store64(s, 0, stamp)
    if Machine.load64(Machine.static(:mcache_mode, 8), 0) == 0
      Machine.store64(Machine.static(:site_stamp, 8), 0, stamp)
    end
    zr_consts_changed()
  end

  # The entry for `mid` on `klass` or an ancestor, or 0. An undef found on
  # the way also gives 0.
  #: (value, word) -> ptr
  def zr_search_method(klass, mid)
    while klass != QNIL
      e = zr_find_method_at(klass, mid)
      if e != 0
        if MEntry[e].kind == KIND_UNDEF
          return 0
        end
        # The frame of the call uses this as the class where it was defined.
        Task[zr_task()].found = klass
        return e
      end
      klass = RClass[klass].superclass
    end
    0
  end

  # The same result as a walk, from the cache while the cache has one.
  # Each send comes through here, so the statics are read where they are
  # used: a helper for each costs more than it saves.
  #: (value, word) -> ptr
  def zr_find_method(klass, mid)
    # A refinement in use is checked at its own position in the ancestor
    # list (zr_refined_search), and the result is kept under its activation
    # list. Thus a site that sees a hundred node classes under `using` (the
    # prism port's `node.reify`) probes as a plain site does.
    refine = Task[zr_task()].refine
    mode = Machine.load64(Machine.static(:mcache_mode, 8), 0)
    if mode == MCACHE_OFF
      return refine == QNIL ? zr_search_method(klass, mid) : zr_refined_search(klass, mid)
    end
    # A cell is CELL_MIN-aligned, so its low bits are always zero.
    h = ((Machine.word(klass) / CELL_MIN) ^ Machine.mul_wrap(mid, 31) ^ (Machine.word(refine) / CELL_MIN)) & (MCACHE_ROWS - 1)
    row = Machine.static(:mcache, MCACHE_ROWS * MCache.size) + (h * MCache.size)
    stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
    if MCache[row].stamp == stamp && MCache[row].klass == klass && MCache[row].mid == mid && MCache[row].refine == refine
      e = MCache[row].entry
      if e != 0
        Task[zr_task()].found = MCache[row].found
      end
      if mode == MCACHE_VERIFY && e != (refine == QNIL ? zr_search_method(klass, mid) : zr_refined_search(klass, mid))
        zr_bug(Machine.bytes("the method cache answered what the chain does not\n"), 50)
      end
      return e
    end
    e = refine == QNIL ? zr_search_method(klass, mid) : zr_refined_search(klass, mid)
    MCache[row].klass = klass
    MCache[row].mid = mid
    MCache[row].entry = e
    MCache[row].found = e == 0 ? Machine.value(QNIL) : Task[zr_task()].found
    MCache[row].stamp = stamp
    MCache[row].refine = refine
    e
  end

  # Whether `recv`'s `mid` is still the core library's own entry, which
  # rb_method_basic_definition_p checks before the C code skips a call.
  #: (value, word) -> bool
  def zr_basic_method_p(recv, mid)
    e = zr_find_method(zr_class_of(recv), mid)
    e != 0 && MEntry[e].core != 0
  end

  # The same for the core: `Primitive.zr_basic_method_m(self, :each)`.
  #: (value, value) -> value
  def zr_basic_method_m(recv, name)
    zr_bool(zr_basic_method_p(recv, zr_sym2id(name)))
  end

  #: (value) -> value
  def zr_class_of(v)
    # A heap object first, with its class in its header: the low three bits
    # of a cell are clear and its address is above all special values. A
    # fixnum is odd, a flonum ends in 10, and a symbol in 1100.
    if (Machine.word(v) & 7) == 0 && Machine.word(v) > QUNDEF
      return RBasic[v].klass
    end
    if zr_fixnum_p(v)
      zr_global(G_INTEGER)
    elsif v == QNIL
      zr_global(G_NIL)
    elsif v == QTRUE
      zr_global(G_TRUE)
    elsif v == QFALSE
      zr_global(G_FALSE)
    elsif zr_symbol_p(v)
      zr_global(G_SYMBOL)
    elsif zr_flonum_p(v)
      zr_global(G_FLOAT)
    else
      RBasic[v].klass
    end
  end

  # Whether `klass` is `target`, inherits from it, or includes it.
  # `supers` is the classes in a class's ancestor list, the nearest last,
  # and `rank` is their count: `supers[d]` is the ancestor at depth `d`.
  # Thus a class `c` is an ancestor when its rank is at most `klass`'s and
  # `supers[rank(c) - 1]` is `c`: one step, where a walk takes one step per
  # ancestor. It is built at the first call from the ancestor list, without
  # proxies. An ancestor list that does not get to BasicObject (a class from
  # `Class.allocate`, not yet initialized) stays unbuilt, because its
  # superclass is not set yet. The rank is 0 for it.
  #: (value) -> word
  def zr_class_rank(klass)
    ext = RClass[klass].ext
    if ClassExt[ext].supers != 0
      return ClassExt[ext].rank
    end
    n = 0
    top = klass
    k = klass
    while k != QNIL
      if (RBasic[k].flags & T_MASK) == T_CLASS
        n += 1
        top = k
      end
      k = RClass[k].superclass
    end
    if top != zr_global(G_BASIC_OBJECT)
      return 0
    end
    s = zr_xmalloc(n * 8)
    i = n
    k = klass
    while k != QNIL
      if (RBasic[k].flags & T_MASK) == T_CLASS
        i -= 1
        Machine.store64(s + (i * 8), 0, Machine.word(k))
      end
      k = RClass[k].superclass
    end
    ClassExt[ext].supers = s
    ClassExt[ext].rank = n
    zr_class_ranked(klass)
    n
  end

  # Sets FL_RANKED on `klass` when its table contains Object and no box
  # has touched it (zr_box_bind clears the flag). With it, a site does a
  # type check with two ranks and one load, and a `nil?` with only the
  # flag. A BasicObject's class has neither.
  #: (value) -> void
  def zr_class_ranked(klass)
    ext = RClass[klass].ext
    o = zr_global(G_OBJECT)
    if o == QFALSE || ClassExt[ext].boxed != QNIL || ClassExt[ext].shadow != QNIL
      return
    end
    ro = zr_class_rank(o)
    if ro != 0 && ro <= ClassExt[ext].rank && Machine.value(Machine.load64(ClassExt[ext].supers + ((ro - 1) * 8), 0)) == o
      RBasic[klass].flags = RBasic[klass].flags | FL_RANKED
    end
  end

  # Whether `target` is in `klass`'s ancestor list. For two classes it
  # uses the superclass list, else a walk.
  #: (value, value) -> bool
  def zr_class_inherits(klass, target)
    if !zr_special_p(target) && !zr_special_p(klass) && (RBasic[target].flags & T_MASK) == T_CLASS && (RBasic[klass].flags & T_MASK) == T_CLASS
      r = zr_class_rank(target)
      n = zr_class_rank(klass)
      if r != 0 && n != 0
        return r <= n && Machine.value(Machine.load64(ClassExt[RClass[klass].ext].supers + ((r - 1) * 8), 0)) == target
      end
    end
    zr_chain_includes(klass, target)
  end

  #: (value, value) -> bool
  def zr_is_a(v, klass)
    k = zr_class_of(v)
    if ClassExt[RClass[k].ext].boxed != QNIL
      k = zr_box_view(k)
    end
    if zr_class_inherits(k, klass)
      return true
    end
    # A box shadow is in place of the shared class, so the shadow responds
    # to what the shared class responds to.
    o = zr_box_origin(klass)
    o != QNIL && zr_class_inherits(k, o)
  end

  # Marks a method table's crefs, and the Procs of block-defined methods.
  #: (ptr) -> void
  def zr_mark_mtab(ext)
    zr_mark_entries(ClassExt[ext].mtab, ClassExt[ext].mlen)
    zr_mark_entries(ClassExt[ext].saved, ClassExt[ext].slen)
  end

  # Marks what `n` method entries from `tab` contain: a cref or a body,
  # the node that a copy came from, and a define_method body's own cref.
  #: (ptr, word) -> void
  def zr_mark_entries(tab, n)
    i = 0
    while i < n
      zr_mark_entry(tab + (i * MEntry.size))
      i += 1
    end
  end

  #: (ptr) -> void
  def zr_mark_entry(e)
    zr_mark(MEntry[e].cref)
    zr_mark(MEntry[e].from)
    if MEntry[e].kind == KIND_BMETHOD
      zr_mark(zr_bmethod_cref_kept(e))
    end
  end

  # Marks what a cell contains in addition to its class, by type, with the
  # common kinds first. A String or a Float contains no Value, and
  # zr_mark_cell handles those without a queue.
  #: (value) -> void
  def zr_mark_children(v)
    t = RBasic[v].flags & T_MASK
    if t == T_OBJECT
      zr_mark_ivtab(Machine.ptr(RObject[v].iv))
    elsif t == T_ARRAY
      zr_mark_ary(v)
    elsif t == T_HASH
      zr_mark_hash(v)
    elsif t == T_STRING || t == T_FLOAT
      return
    elsif t == T_ICLASS
      zr_mark(RClass[v].superclass)
      zr_mark(RClass[v].attached)
      if RClass[RClass[v].attached].origin == v
        zr_mark_mtab(RClass[v].ext)
      end
    elsif t == T_CLASS || t == T_MODULE
      zr_mark(RClass[v].name)
      zr_mark(RClass[v].superclass)
      zr_mark(RClass[v].attached)
      ext = RClass[v].ext
      zr_mark_mtab(ext)
      n = ClassExt[ext].clen
      i = 0
      while i < n
        zr_mark(CEntry[ClassExt[ext].ctab + (i * CEntry.size)].value)
        i += 1
      end
      zr_mark_ivtab(Machine.ptr(ClassExt[ext].iv))
      zr_mark_ivtab(Machine.ptr(ClassExt[ext].cv))
      zr_mark(ClassExt[ext].refined)
      zr_mark(ClassExt[ext].active)
      zr_mark(ClassExt[ext].boxed)
      zr_mark(ClassExt[ext].shadow)
    elsif t == T_EXCEPTION
      zr_mark(RException[v].message)
      zr_mark(RException[v].bt)
      if RException[v].cause != QUNDEF
        zr_mark(RException[v].cause)
      end
      zr_mark_backtrace_rows(v)
    elsif t == T_CREF
      zr_mark(RCref[v].klass)
      zr_mark(RCref[v].lazy)
      zr_mark(RCref[v].next)
    elsif t == T_ENV
      zr_mark_env(v)
    elsif t == T_PROC
      zr_mark_proc(v)
    elsif t == T_METHOD
      zr_mark_method(v)
    elsif t == T_FIBER
      zr_mark_fiber(v)
    elsif t == T_REGEXP
      zr_mark_regexp(v)
    end
  end

  # Frees what a cell owns outside the arena. The kinds that a sweep frees
  # in large numbers come first, each with one check. The others, and the
  # caches that a freed class or cref must clear, go to zr_release_other.
  #: (value) -> void
  def zr_release(v)
    t = RBasic[v].flags & T_MASK
    if t == T_OBJECT
      zr_release_ivtab(Machine.ptr(RObject[v].iv))
    elsif t == T_STRING
      zr_str_buf_free(v)
    elsif t == T_ARRAY
      zr_ary_buf_free(v)
    elsif t == T_HASH
      zr_sized_xfree(RHash[v].entries, RHash[v].cap * HEntry.size)
      zr_sized_xfree(RHash[v].bins, RHash[v].nbins * 8)
    else
      zr_release_other(v, t)
    end
  end

  #: (value, word) -> void
  def zr_release_other(v, t)
    if t == T_ICLASS || t == T_CLASS || t == T_MODULE
      # A freed class's address can go to another class, so a method cache
      # entry with it as key must not match the new class.
      zr_methods_changed()
    end
    if t == T_CREF
      # The same applies to a cref's address, and a constant cache entry
      # uses one as key.
      zr_consts_changed()
    end
    if t == T_ICLASS
      if RClass[RClass[v].attached].origin == v
        if ClassExt[RClass[v].ext].mtab != 0
          zr_xfree(ClassExt[RClass[v].ext].mtab)
        end
        zr_method_index_drop(RClass[v].ext)
        zr_xfree(RClass[v].ext)
      end
    elsif t == T_CLASS || t == T_MODULE
      ext = RClass[v].ext
      if ClassExt[ext].mtab != 0
        zr_xfree(ClassExt[ext].mtab)
      end
      if ClassExt[ext].saved != 0
        zr_xfree(ClassExt[ext].saved)
      end
      if ClassExt[ext].ctab != 0
        zr_xfree(ClassExt[ext].ctab)
      end
      if ClassExt[ext].supers != 0
        zr_xfree(ClassExt[ext].supers)
      end
      zr_method_index_drop(ext)
      zr_const_index_drop(ext)
      zr_release_ivtab(Machine.ptr(ClassExt[ext].iv))
      zr_release_ivtab(Machine.ptr(ClassExt[ext].cv))
      zr_xfree(ext)
    elsif t == T_EXCEPTION
      if RException[v].rows != 0
        zr_xfree(RException[v].rows)
      end
    elsif t == T_FIBER
      zr_release_fiber(v)
    elsif t == T_REGEXP
      zr_release_regexp(v)
    elsif t == T_ENV
      zr_xfree(REnv[v].slots)
    end
  end

  # `set_temporary_name`: a name that a later constant assignment
  # replaces; nil clears it. Returns whether the module had a permanent
  # name, which cannot change.
  #: (value, value) -> value
  def zr_mod_set_temporary_name(mod, name)
    if RClass[mod].name != QNIL && (RBasic[mod].flags & FL_TEMP_NAME) == 0
      return Machine.value(QFALSE)
    end
    RClass[mod].name = name
    if name == QNIL
      RBasic[mod].flags = RBasic[mod].flags & (0 - (FL_TEMP_NAME + 1))
    else
      RBasic[mod].flags = RBasic[mod].flags | FL_TEMP_NAME
    end
    Machine.value(QTRUE)
  end

  # --- refinements -------------------------------------------------------

  G_REFINEMENT = 46
  # One activation entry for each `using` in the program. A call site
  # refers to the entry that applies to it.
  G_ACTIVATIONS = 47

  # The holder module that `refine` makes: a usual module that knows the
  # class it refines. Its activation list is `active`, which all
  # refinements of the same module share, as rb_mod_refine shares
  # activated_refinements. Thus a call in one refine block finds the
  # module's other refinements, also the later ones.
  #: (value, value) -> value
  def zr_refinement_new(klass, active)
    h = zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_REFINEMENT))
    ext = RClass[h].ext
    ClassExt[ext].refined = klass
    zr_write_barrier(h, klass)
    zr_ary_push(active, h)
    ClassExt[ext].active = active
    zr_write_barrier(h, active)
    h
  end

  #: (value) -> value
  def zr_refined_class(h)
    ClassExt[RClass[h].ext].refined
  end

  # The current value of activation entry `id`. An entry whose `using` a
  # condition skipped contains the id of the entry before it, which is used
  # in its place. An entry that nothing has touched contains nil.
  #: (value, word) -> value
  def zr_activation_row(rows, id)
    if zr_special_p(rows) || id < 0 || id >= RArray[rows].len
      return Machine.value(QNIL)
    end
    row = zr_ary_at(rows, id)
    while zr_fixnum_p(row)
      from = zr_fix2long(row)
      row = Machine.value(QNIL)
      if from >= 0 && from < RArray[rows].len
        row = zr_ary_at(rows, from)
      end
    end
    row
  end

  # The activation list that a call site refers to, which each send under
  # it reads.
  #: (word) -> value
  def zr_activate(id)
    Task[zr_task()].refine = zr_activation_row(zr_global(G_ACTIVATIONS), id)
    Machine.value(QNIL)
  end

  # In a `refine` block, the refinement that it defines is in use, so a
  # sibling method is available by its bare name.
  #: (ptr) -> value
  def zr_activate_owner(rec)
    meta = zr_method_meta_of(rec)
    list = Machine.value(QNIL)
    if meta != 0
      owner = FrameMeta[meta].owner
      if !zr_special_p(owner) && (zr_type(owner) == T_MODULE || zr_type(owner) == T_CLASS)
        list = ClassExt[RClass[owner].ext].active
      end
    end
    Task[zr_task()].refine = list
    Machine.value(QNIL)
  end

  # The table of activation entries, long enough to contain entry `id`.
  #: (word) -> value
  def zr_activation_rows(id)
    rows = zr_global(G_ACTIVATIONS)
    if zr_special_p(rows)
      rows = zr_ary_new(8)
      zr_set_global(G_ACTIVATIONS, rows)
    end
    while RArray[rows].len <= id
      zr_ary_push(rows, Machine.value(QNIL))
    end
    rows
  end

  # Reserves each entry that the program was compiled with, before its
  # first line. Else an entry is made where its `using` runs, and one under
  # a condition that is never true is never made. Then the table alone
  # does not give the program's entry count, and a compile at run time
  # could reuse an entry number that the program already has.
  #: (word) -> value
  def zr_activations_reserve(count)
    if count > 0
      zr_activation_rows(count - 1)
    end
    Machine.value(QNIL)
  end

  # The same, plus the count of reserved entries, for the compiled compiler
  # in a program: it numbers a snippet's entries after them, then reserves
  # them.
  #: (value) -> value
  def zr_activations_reserve_m(count)
    zr_activations_reserve(zr_fix2long(count))
  end

  #: () -> value
  def zr_activations_count
    rows = zr_global(G_ACTIVATIONS)
    zr_fix(zr_special_p(rows) ? 0 : RArray[rows].len)
  end

  # A `using` under a condition can never run. Until it runs, its entry
  # refers to entry `from`, with the value that entry has when a call reads
  # it. An entry that a `using` already filled keeps its own value.
  #: (word, word) -> value
  def zr_using_default(id, from)
    rows = zr_activation_rows(id)
    if zr_ary_at(rows, id) == QNIL
      zr_ary_store(rows, id, zr_fix(from))
    end
    Machine.value(QNIL)
  end

  # `using mod` at entry `id`: the entries in `from` now, then each holder
  # that `mod` refines. `from` is -1 when nothing was in use.
  #: (word, value, word) -> value
  def zr_using_activate(id, mod, from)
    rows = zr_activation_rows(id)
    list = zr_ary_new(4)
    prior = zr_activation_row(rows, from)
    if prior != QNIL
      zr_ary_splat(list, prior)
    end
    r = zr_using_holders(list, mod)
    return r if r == QUNDEF
    zr_ary_store(rows, id, list)
    # A site under this entry can have cache entries filled under the entry
    # that it replaces (SEND_USING).
    zr_methods_changed()
    Machine.value(QNIL)
  end

  # Appends each holder that `mod` refines to `list`. `Module#refinements`
  # returns them, so a module written in Ruby also works.
  #: (value, value) -> value
  def zr_using_holders(list, mod)
    if zr_special_p(mod) || zr_type(mod) != T_MODULE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_class_of(b, mod)
      zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    found = zr_send(mod, Machine.id(:refinements), 0, 0)
    return found if found == QUNDEF
    zr_ary_splat(list, found)
  end

  # The class that an activation entry's element refines, or nil for
  # anything else in the entry. The entry is filled from
  # `Module#refinements`, which is Ruby, and a program can return any value
  # from it.
  #: (value) -> value
  def zr_refined_target(h)
    if zr_special_p(h) || zr_type(h) != T_MODULE
      return Machine.value(QNIL)
    end
    ClassExt[RClass[h].ext].refined
  end

  # Whether a holder for `target` comes before `stop` in the entry.
  #: (value, value, word) -> bool
  def zr_refined_target_seen_p(list, target, stop)
    i = 0
    while i < stop
      if zr_refined_target(zr_ary_at(list, i)) == target
        return true
      end
      i += 1
    end
    false
  end

  # `Module.used_refinements`: each refinement in force at the caller, in
  # CRuby's order. CRuby's table has the refined class as key and the head
  # of that class's list as value. Thus its result is the refined classes
  # in the order that a `using` first found them and, for each, the newest
  # refinement first. The activation entry is one flat list in `using`
  # order, so one walk for each distinct target gives both orders.
  #
  # This is a builtin because a compiled Ruby frame starts with no
  # refinements in use (they belong to the call site, not to the method it
  # called). A builtin's frame keeps the entry that the site filled.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_used_refinements(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    list = Task[zr_task()].refine
    if zr_special_p(list) || zr_type(list) != T_ARRAY
      return out
    end
    n = RArray[list].len
    i = 0
    while i < n
      target = zr_refined_target(zr_ary_at(list, i))
      if target != QNIL && !zr_refined_target_seen_p(list, target, i)
        k = n - 1
        while k >= 0
          h = zr_ary_at(list, k)
          if zr_refined_target(h) == target
            zr_ary_push(out, h)
          end
          k -= 1
        end
      end
      i += 1
    end
    out
  end

  # `Module.used_modules`: the module where each refinement in use was
  # written, in the same order and without duplicates. A module that
  # refines two classes is in two lists, and CRuby removes duplicates.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_used_modules(recv, argc, argv, cref, blk)
    found = zr_mod_used_refinements(recv, argc, argv, cref, blk)
    out = zr_ary_new(4)
    i = 0
    while i < RArray[found].len
      origin = zr_ivar_get(zr_ary_at(found, i), Machine.id(:__origin__))
      if zr_ary_index_of(out, origin) < 0
        zr_ary_push(out, origin)
      end
      i += 1
    end
    out
  end

  # The lookup walk with refinements in use. At each node of the ancestor
  # list, a refinement of that node's class or module comes before the
  # node's own table. Thus a subclass's own method still wins over a
  # refinement of its ancestor, as CRuby resolves a refined entry where the
  # refined class is.
  #: (value, word) -> ptr
  def zr_refined_search(klass, mid)
    k = klass
    while k != QNIL
      e = zr_refined_entry_at(zr_type(k) == T_ICLASS ? RClass[k].attached : k, mid)
      if e != 0
        return e
      end
      e = zr_find_method_at(k, mid)
      if e != 0
        if MEntry[e].kind == KIND_UNDEF
          return 0
        end
        Task[zr_task()].found = k
        return e
      end
      k = RClass[k].superclass
    end
    0
  end

  # The entry that a refinement in use gives for `mid` on `target` itself,
  # newest first, or 0.
  #: (value, word) -> ptr
  def zr_refined_entry_at(target, mid)
    list = Task[zr_task()].refine
    if zr_special_p(list) || zr_type(list) != T_ARRAY
      return 0
    end
    i = RArray[list].len - 1
    while i >= 0
      h = zr_ary_at(list, i)
      if !zr_special_p(h) && zr_type(h) == T_MODULE && ClassExt[RClass[h].ext].refined == target
        e = zr_search_method(h, mid)
        if e != 0
          return e
        end
      end
      i -= 1
    end
    0
  end

  # The refinement where the last lookup found its entry, or nil. A Method
  # made from a refined name is owned by its holder.
  #: () -> value
  def zr_found_refinement
    f = Task[zr_task()].found
    if !zr_special_p(f) && zr_type(f) == T_MODULE && ClassExt[RClass[f].ext].refined != QNIL
      return f
    end
    Machine.value(QNIL)
  end
end
