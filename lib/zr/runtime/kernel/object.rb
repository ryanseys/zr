module Zr::Kern
  # Objects: a class and an ivar table of (id, value) ivar entries. A
  # class or module keeps the same table in its extension. An object's
  # first ivar entries are in its cell after the table. Entries past them
  # are malloc'd, and a release or a copy frees only those. A site reads
  # and writes the ivar entry at its cached index inline (the lowering's
  # `guessed_ivar_row`), and calls here for all other cases. This file
  # also contains reflection, identity, inspect and p.
  # `names` has bit `id & 63` set for each name that an ivar entry got. A
  # clear bit shows, with no scan, that no entry contains the name. A
  # removed entry keeps its bit.
  class IvTab < Layout
    attr_accessor :rows #: ptr
    attr_accessor :len #: word
    attr_accessor :cap #: word
    attr_accessor :names #: word
  end

  class IvEntry < Layout
    attr_accessor :id #: word
    attr_accessor :value #: value
  end

  class RObject < Layout
    attr_reader :basic #: RBasic
    attr_reader :iv #: IvTab
  end

  #: (ptr) -> void
  def zr_ivtab_init(t)
    IvTab[t].rows = 0
    IvTab[t].len = 0
    IvTab[t].cap = 0
    IvTab[t].names = 0
  end

  # The bit of `IvTab.names` that represents `id`.
  #: (word) -> word
  def zr_ivtab_name_bit(id)
    Machine.shl_wrap(Machine.word(1), id & 63)
  end

  # Returns the ivar table of `v`, or 0 when it has none. This is the
  # table of the object or class itself, else the table kept next to the
  # arena.
  #: (value) -> ptr
  def zr_ivtab(v)
    if zr_special_p(v)
      return 0
    end
    t = RBasic[v].flags & T_MASK
    if t == T_OBJECT
      Machine.ptr(RObject[v].iv)
    elsif t == T_CLASS || t == T_MODULE
      Machine.ptr(ClassExt[RClass[v].ext].iv)
    elsif (RBasic[v].flags & FL_EXIVAR) != 0
      zr_exivar_tab(v)
    else
      0
    end
  end

  # Returns the table for a write. It makes the table when the type has no
  # table of its own. A special constant is frozen.
  #: (value) -> ptr
  def zr_ivtab_for_write(v)
    t = zr_ivtab(v)
    if t != 0
      return t
    end
    if zr_special_p(v)
      return 0
    end
    zr_exivar_tab_for_write(v)
  end

  #: (ptr) -> void
  def zr_mark_ivtab(t)
    n = IvTab[t].len
    i = 0
    while i < n
      zr_mark(IvEntry[IvTab[t].rows + (i * IvEntry.size)].value)
      i += 1
    end
  end

  #: (ptr) -> void
  def zr_release_ivtab(t)
    if !zr_ivtab_embedded_p(t)
      zr_sized_xfree(IvTab[t].rows, IvTab[t].cap * IvEntry.size)
    end
  end

  # Whether `t`'s ivar entries are in the cell immediately after the
  # table, which is the T_OBJECT layout of `zr_obj_ivtab_init`. The address
  # alone is not sufficient: a heap table whose entries were allocated
  # immediately after its header gives the same result, and a bump
  # allocator makes that case common. Thus, call this only for a table
  # that an object owns, where the entries are in the cell or on the heap
  # and nothing else can be between.
  #: (ptr) -> bool
  def zr_ivtab_embedded_p(t)
    IvTab[t].rows == t + IvTab.size
  end

  # Returns the object whose cell contains `t`'s ivar entries, or nil when
  # they are on the heap. Only a T_OBJECT keeps its entries in its own
  # cell, so only a T_OBJECT can return non-nil.
  #: (value) -> value
  def zr_ivtab_owner(obj)
    if !zr_special_p(obj) && (RBasic[obj].flags & T_MASK) == T_OBJECT
      return obj
    end
    Machine.value(QNIL)
  end

  # Makes an instance of `klass` in a cell of the size that the class's
  # instances needed until now (ClassExt.obj_bytes): one ivar entry in 64
  # bytes, 5 in 128, 13 in 256.
  #: (value) -> value
  def zr_obj_alloc(klass)
    o = zr_alloc(T_OBJECT, klass, ClassExt[RClass[klass].ext].obj_bytes)
    zr_obj_ivtab_init(o)
    o
  end

  # An object's table became too large for its cell. The class's next
  # instances get a cell with space for `n` ivar entries, or the largest
  # cell.
  #: (value, word) -> void
  def zr_obj_ivars_seen(o, n)
    ext = RClass[zr_real_class(o)].ext
    bytes = RObject.size + (n * IvEntry.size)
    if bytes > CELL_MAX
      bytes = CELL_MAX
    end
    if bytes > ClassExt[ext].obj_bytes
      ClassExt[ext].obj_bytes = bytes
    end
  end

  # Sets up an empty object table, with its ivar entries in the object's
  # own cell.
  #: (value) -> void
  def zr_obj_ivtab_init(o)
    t = Machine.ptr(RObject[o].iv)
    IvTab[t].rows = t + IvTab.size
    IvTab[t].len = 0
    IvTab[t].cap = (zr_cell_bytes(o) - RObject.size) / IvEntry.size
    IvTab[t].names = 0
  end

  # Returns the ivar entry for `id` in the table `t`, or 0.
  #: (ptr, word) -> ptr
  def zr_ivtab_row(t, id)
    if (IvTab[t].names & zr_ivtab_name_bit(id)) == 0
      return 0
    end
    n = IvTab[t].len
    i = 0
    while i < n
      e = IvTab[t].rows + (i * IvEntry.size)
      if IvEntry[e].id == id
        return e
      end
      i += 1
    end
    0
  end

  # Returns the value for `id` in the table, or undef.
  #: (ptr, word) -> value
  def zr_ivtab_get(t, id)
    e = zr_ivtab_row(t, id)
    if e == 0
      return Machine.value(QUNDEF)
    end
    IvEntry[e].value
  end

  # An instance variable of a shareable object that can still change
  # belongs only to the main ractor. A Ractor is such an object, because
  # its contents are not frozen. Any ractor can read a deeply frozen
  # graph, because nothing can change it, and a write to it raises a
  # frozen error. A Ractor keeps its own state in hidden slots, which have
  # no `@` and no program can refer to. Thus each instance variable of a
  # Ractor here belongs to the program and follows the program's rule.
  #: (value) -> value
  def zr_ractor_guard(obj)
    t = zr_task()
    if Task[t].ractor == 0
      return Machine.value(QNIL)
    end
    if zr_frozen_p(obj) || zr_class_of(obj) != zr_core_class(Machine.id(:Ractor))
      return Machine.value(QNIL)
    end
    zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:isolation!), 0, 0)
  end

  #: (value, word) -> value
  def zr_ivar_defined(obj, id)
    g = zr_ractor_guard(obj)
    if g == QUNDEF
      return g
    end
    t = zr_ivtab(obj)
    if t == 0
      return Machine.value(QFALSE)
    end
    zr_bool(zr_ivtab_row(t, id) != 0)
  end

  # `defined?(recv.name)`: whether the call can reach a method. A private
  # method with an explicit receiver does not count, and a protected
  # method from outside the owner does not count.
  #: (value, word, bool) -> value
  def zr_method_defined(recv, id, explicit)
    e = zr_find_method(zr_box_view(zr_class_of(recv)), id)
    if e == 0
      return zr_bool(zr_respond_to_missing_p(recv, id))
    end
    if explicit && MEntry[e].vis == VIS_PRIVATE
      return Machine.value(QFALSE)
    end
    if explicit && MEntry[e].vis == VIS_PROTECTED && !zr_is_a(Frame[Task[zr_task()].top].self, FrameMeta[MEntry[e].meta].owner)
      return Machine.value(QFALSE)
    end
    Machine.value(QTRUE)
  end

  # A receiver with no table returns nil.
  #: (value, word) -> value
  def zr_ivar_get(obj, id)
    t = zr_ivtab(obj)
    if t == 0
      return Machine.value(QNIL)
    end
    v = zr_ivtab_get(t, id)
    if v == QUNDEF
      return Machine.value(QNIL)
    end
    v
  end

  # A hidden instance variable has a name with no `@`. `instance_variables`
  # and `inspect` do not show it, and no Ruby name can refer to it. Struct
  # keeps its members and values in them, as CRuby does.
  #: (value, value) -> value
  def zr_hidden_get(obj, name)
    zr_ivar_get(obj, zr_sym2id(name))
  end

  #: (value, value, value) -> value
  def zr_hidden_set(obj, name, v)
    zr_ivar_set(obj, zr_sym2id(name), v)
  end

  # Core-only state that `freeze` does not lock: a frozen Mutex can still
  # lock, as with the C fields of CRuby's Mutex.
  #: (value, value, value) -> value
  def zr_state_set(obj, name, v)
    zr_ivtab_set_in(zr_ivtab_for_write(obj), zr_sym2id(name), v, zr_ivtab_owner(obj))
    zr_write_barrier(obj, v)
    v
  end

  # An object that a ractor moved away. Its class becomes the husk class,
  # so each message that it gets finds only methods that raise. The cell
  # keeps its type, so the collector still scans it as that type.
  #: (value, value) -> value
  def zr_moved_m(obj, klass)
    if zr_special_p(obj)
      return Machine.value(QNIL)
    end
    RBasic[obj].klass = klass
    Machine.value(QNIL)
  end

  # `object_id`: 2n + 1 for a fixnum, 4 for nil, 20 for true, 0 for false.
  # A heap object gets a value from a counter (8, 16, 24, ...) at its first
  # call, kept in a hidden ivar. For a symbol or a flonum it is the word,
  # as in CRuby, so a symbol's value is different from CRuby's by the id.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_object_id(recv, argc, argv, cref, blk)
    if zr_fixnum_p(recv)
      # 2n+1, which leaves the fixnum range near its ends.
      return zr_int_from_word((zr_fix2long(recv) * 2) + 1)
    end
    if recv == QNIL
      return zr_fix(4)
    end
    if recv == QTRUE
      return zr_fix(20)
    end
    if recv == QFALSE
      return zr_fix(0)
    end
    if zr_special_p(recv)
      # The word itself, also outside the fixnum range, as in CRuby.
      return zr_int_from_word(Machine.word(recv))
    end
    t = zr_ivtab_for_write(recv)
    id = zr_ivtab_get(t, Machine.id(:__object_id__))
    if id != QUNDEF
      return id
    end
    counter = Machine.static(:object_id_counter, 8)
    n = Machine.load64(counter, 0) + 8
    Machine.store64(counter, 0, n)
    id = zr_fix(n)
    zr_ivtab_set_in(t, Machine.id(:__object_id__), id, zr_ivtab_owner(recv))
    zr_write_barrier(recv, id)
    id
  end

  # Whether an instance variable's name is visible: it starts with `@`.
  #: (word) -> bool
  def zr_ivar_id_visible_p(id)
    Machine.u8(Machine.load8(zr_symbol_name_ptr(id), 0)) == 64
  end

  #: (value, word, value) -> value
  def zr_ivar_set(obj, id, v)
    if zr_modify_frozen_p(obj)
      return zr_frozen_error(obj)
    end
    t = zr_ivtab_for_write(obj)
    zr_ivtab_set_in(t, id, v, zr_ivtab_owner(obj))
    zr_write_barrier(obj, v)
    v
  end

  # Sets an entry in a table that no object owns: the class variables,
  # the globals, the caches. Their entries are always on the heap.
  #: (ptr, word, value) -> void
  def zr_ivtab_set(t, id, v)
    zr_ivtab_set_in(t, id, v, Machine.value(QNIL))
  end

  #: (ptr, word, value, value) -> void
  def zr_ivtab_set_in(t, id, v, owner)
    e = zr_ivtab_row(t, id)
    if e == 0
      zr_ivtab_append(t, id, v, owner)
    else
      IvEntry[e].value = v
    end
  end

  # Adds an entry for `id`, which no entry contains yet, after the last
  # entry. The entries grow when full.
  #: (ptr, word, value, value) -> void
  def zr_ivtab_append(t, id, v, owner)
    n = IvTab[t].len
    if n == IvTab[t].cap
      cap = n * 2
      if cap < 4
        cap = 4
      end
      rows = zr_xmalloc(cap * IvEntry.size)
      if IvTab[t].rows != 0
        zr_memcpy(rows, IvTab[t].rows, n * IvEntry.size)
        # Entries in the cell stay where they are, and the class records
        # that its objects need space for one more. Otherwise, the old
        # entries are a heap block that the table no longer needs.
        if owner != QNIL && zr_ivtab_embedded_p(t)
          zr_obj_ivars_seen(owner, n + 1)
        else
          zr_sized_xfree(IvTab[t].rows, IvTab[t].cap * IvEntry.size)
        end
      end
      IvTab[t].rows = rows
      IvTab[t].cap = cap
    end
    e = IvTab[t].rows + (n * IvEntry.size)
    IvEntry[e].id = id
    IvTab[t].len = n + 1
    IvTab[t].names = IvTab[t].names | zr_ivtab_name_bit(id)
    IvEntry[e].value = v
  end

  # A Range is a plain frozen object of class Range with three ivars. Its
  # methods are in the core library.
  G_RANGE = 12
  G_RANGE_LITERALS = 51

  # Returns the object that a literal's site made, from the table in
  # global `g`, or nil before the site runs.
  #
  # The table is a Hash keyed by the site's index, not an Array. All sites
  # in the program (each call cache too) get an index from one counter, so
  # a literal's index can be tens of thousands. An Array of that length
  # would contain that many nils, which the collector reads at each
  # collection.
  #: (word, word) -> value
  def zr_site_literal(g, index)
    table = zr_global(g)
    if zr_special_p(table)
      return Machine.value(QNIL)
    end
    found = zr_hash_lookup(table, zr_fix(index))
    found == QUNDEF ? Machine.value(QNIL) : found
  end

  #: (word, word, value) -> void
  def zr_site_literal_set(g, index, v)
    table = zr_global(g)
    if zr_special_p(table)
      table = zr_hash_new()
      zr_set_global(g, table)
    end
    zr_hash_store(table, zr_fix(index), v)
  end

  # A range literal whose ends are Integer or nil literals. It is made the
  # first time its site runs, and after that it is the same frozen object,
  # as with CRuby's putobject. The literal table keeps it by the site's
  # index.
  #: (word, value, value, word) -> value
  def zr_range_literal(index, low, high, excl)
    r = zr_site_literal(G_RANGE_LITERALS, index)
    if r != QNIL
      return r
    end
    r = zr_range_new(low, high, excl)
    return r if r == QUNDEF
    zr_site_literal_set(G_RANGE_LITERALS, index, r)
    r
  end

  # Writes the first and the last fixnum of `range` into `out`, when both
  # ends are fixnums (an exclusive end gives one less). A site uses them to
  # run `each` inline (Function::Iterators). Returns false for any other
  # Range, which then makes the call.
  #: (value, ptr) -> bool
  def zr_range_fix_bounds(range, out)
    low = zr_ivar_get(range, Machine.id(:begin))
    high = zr_ivar_get(range, Machine.id(:end))
    if !zr_fixnum_p(low) || !zr_fixnum_p(high)
      return false
    end
    Machine.store64(out, 0, Machine.word(low))
    last = Machine.word(high)
    if zr_ivar_get(range, Machine.id(:excl)) != QFALSE
      last -= 2
    end
    # The site increments past the last value before it compares again,
    # and the largest fixnum has no word after it.
    if last == 9223372036854775807
      return false
    end
    Machine.store64(out, 8, last)
    true
  end

  #: (value, value, word) -> value
  def zr_range_new(low, high, excl)
    if low != QNIL && high != QNIL && !(zr_fixnum_p(low) && zr_fixnum_p(high))
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(high))
      c = zr_send(low, Machine.id(:<=>), 1, slot)
      return c if c == QUNDEF
      if c == QNIL
        return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("bad value for range"), 19)
      end
    end
    r = zr_obj_alloc(zr_global(G_RANGE))
    zr_ivar_set(r, Machine.id(:begin), low)
    zr_ivar_set(r, Machine.id(:end), high)
    zr_ivar_set(r, Machine.id(:excl), zr_bool(excl != 0))
    RBasic[r].flags = RBasic[r].flags | FL_FREEZE
    r
  end

  # `Class#allocate`: returns an uninitialized object of the type that the
  # class's builtin ancestor gives. Raises CRuby's TypeError for a class
  # whose allocator is undefined.
  #: (value) -> value
  def zr_class_allocate(recv)
    recv = zr_alloc_class(recv)
    # The checks of CRuby's class_call_alloc_func, in the same order.
    if RClass[recv].superclass == QNIL && recv != zr_global(G_BASIC_OBJECT)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't instantiate uninitialized class"), 37)
    end
    if (RBasic[recv].flags & FL_SINGLETON) != 0
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't create instance of singleton class"), 40)
    end
    kind = zr_alloc_kind(recv)
    if zr_alloc_undefined_p(kind)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("allocator undefined for "), 24)
      zr_buf_class(b, recv)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    zr_alloc_shape(recv, kind)
  end

  # Returns the object that a core constructor builds for its class, also
  # when Ruby cannot call `allocate` on it. CRuby's Thread.new calls
  # thread_alloc, and Rational's constructors call nurat_s_alloc, the
  # same way.
  #: (value) -> value
  def zr_class_build(recv)
    recv = zr_alloc_class(recv)
    kind = zr_alloc_kind(recv)
    zr_alloc_shape(recv, zr_alloc_undefined_p(kind) ? ALLOC_OBJECT : kind)
  end

  # A box shadow allocates the same type as the class that it is in place
  # of, so main knows the objects that a box makes.
  #: (value) -> value
  def zr_alloc_class(recv)
    shared = zr_box_current() == QNIL ? Machine.value(QNIL) : zr_box_origin(recv)
    shared == QNIL ? recv : shared
  end

  #: (value, word) -> value
  def zr_alloc_shape(recv, kind)
    if kind == ALLOC_OBJECT
      return zr_obj_alloc(recv)
    end
    # A subclass of Class or Module allocates the same type as its
    # ancestor, never a plain object.
    if kind == ALLOC_CLASS
      return zr_class_alloc(T_CLASS, Machine.value(QNIL), recv)
    end
    if kind == ALLOC_MODULE
      return zr_class_alloc(T_MODULE, Machine.value(QNIL), recv)
    end
    if kind == ALLOC_EXCEPTION
      return zr_exc_new(recv, Machine.value(QNIL))
    end
    if kind == ALLOC_REGEXP
      return zr_regexp_alloc(recv)
    end
    if kind == ALLOC_FIBER
      return zr_fiber_alloc(recv)
    end
    if kind == ALLOC_ARRAY
      o = zr_ary_new(4)
    elsif kind == ALLOC_HASH
      o = zr_hash_new()
    else
      # CRuby's allocator makes a binary String. `String.new("x")` then
      # sets the source's encoding.
      o = zr_str_new(Machine.bytes(""), 0)
      zr_str_set_binary(o)
    end
    RBasic[o].klass = recv
    o
  end

  # The type of object that a class allocates: the type that the class or
  # its nearest superclass records, as CRuby's rb_get_alloc_func walks the
  # superclasses. The builtin roots record theirs at boot
  # (zr_alloc_table). Core records the types of its own classes when it
  # defines them (zr_undef_alloc, zr_define_alloc). A class with no record
  # keeps its superclass's type after the first lookup, because a class's
  # superclass never changes.
  ALLOC_OBJECT = 1
  ALLOC_CLASS = 2
  ALLOC_MODULE = 3
  ALLOC_EXCEPTION = 4
  ALLOC_ARRAY = 5
  ALLOC_HASH = 6
  ALLOC_STRING = 7
  ALLOC_UNDEF = 8
  ALLOC_REGEXP = 9
  ALLOC_NONE = 10
  ALLOC_FIBER = 11

  # Whether a class of `kind` has no allocator that Ruby can call.
  # ALLOC_UNDEF is for a class that also has no `new` (Integer, Binding).
  # ALLOC_NONE is for a class whose `new` is still Class#new
  # (Zlib::ZStream).
  #: (word) -> bool
  def zr_alloc_undefined_p(kind)
    kind == ALLOC_UNDEF || kind == ALLOC_NONE
  end

  #: (value) -> word
  def zr_alloc_kind(klass)
    kind = ClassExt[RClass[klass].ext].alloc
    if kind != 0
      return kind
    end
    sup = zr_real_superclass(klass)
    if sup == QNIL
      # A class from `Class.allocate` has no allocator until it gets its
      # superclass, so this result is not kept. A subclass of it keeps the
      # result, as in CRuby, also after the superclass is set.
      return klass == zr_global(G_BASIC_OBJECT) ? ALLOC_OBJECT : ALLOC_NONE
    end
    kind = zr_alloc_kind(sup)
    ClassExt[RClass[klass].ext].alloc = kind
    kind
  end

  #: (word, word) -> void
  def zr_alloc_record(g, kind)
    ClassExt[RClass[zr_global(g)].ext].alloc = kind
  end

  # The allocation types of the builtin roots. The value classes, Proc and
  # the method objects have no allocator that Ruby can call (CRuby's
  # rb_undef_alloc_func), and their subclasses also have none.
  #: () -> void
  def zr_alloc_table
    zr_alloc_record(G_CLASS, ALLOC_CLASS)
    zr_alloc_record(G_MODULE, ALLOC_MODULE)
    zr_alloc_record(G_EXCEPTION, ALLOC_EXCEPTION)
    zr_alloc_record(G_ARRAY, ALLOC_ARRAY)
    zr_alloc_record(G_HASH, ALLOC_HASH)
    zr_alloc_record(G_STRING, ALLOC_STRING)
    zr_alloc_record(G_REGEXP, ALLOC_REGEXP)
    zr_alloc_record(G_INTEGER, ALLOC_UNDEF)
    zr_alloc_record(G_FLOAT, ALLOC_UNDEF)
    zr_alloc_record(G_SYMBOL, ALLOC_UNDEF)
    zr_alloc_record(G_NIL, ALLOC_UNDEF)
    zr_alloc_record(G_TRUE, ALLOC_UNDEF)
    zr_alloc_record(G_FALSE, ALLOC_UNDEF)
    zr_alloc_record(G_PROC, ALLOC_UNDEF)
    zr_alloc_record(G_METHOD, ALLOC_UNDEF)
    zr_alloc_record(G_UNBOUND_METHOD, ALLOC_UNDEF)
    zr_alloc_record(G_FIBER, ALLOC_FIBER)
  end

  # rb_undef_alloc_func, for a class that core defines. `allocate` raises
  # TypeError on it, and on a subclass that records no type of its own.
  #: (value) -> value
  def zr_undef_alloc(klass)
    ClassExt[RClass[klass].ext].alloc = ALLOC_UNDEF
    Machine.value(QNIL)
  end

  # rb_undef_alloc_func only, for a class that an extension defines. `new`
  # stays Class#new, and both `new` and `allocate` raise TypeError.
  #: (value) -> value
  def zr_undef_allocator(klass)
    ClassExt[RClass[klass].ext].alloc = ALLOC_NONE
    Machine.value(QNIL)
  end

  # rb_define_alloc_func with a plain object, for a class that core makes
  # under a class whose allocator is undefined (Struct.new, Data.define).
  #: (value) -> value
  def zr_define_alloc(klass)
    ClassExt[RClass[klass].ext].alloc = ALLOC_OBJECT
    Machine.value(QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_class_allocate_m(recv, argc, argv, cref, blk)
    zr_class_allocate(recv)
  end

  # Returns the object that `Class#new` makes before `initialize` runs.
  # Raises NoMethodError for a class whose allocator is undefined.
  #: (value) -> value
  def zr_class_new_object(recv)
    # A class that recorded plain objects, outside a box and not a
    # singleton, passes each check below: allocate directly.
    if ClassExt[RClass[recv].ext].alloc == ALLOC_OBJECT && (RBasic[recv].flags & FL_SINGLETON) == 0 && zr_box_current() == QNIL
      return zr_obj_alloc(recv)
    end
    if zr_alloc_kind(recv) == ALLOC_UNDEF
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("undefined method 'new' for class "), 33)
      zr_buf_class(b, recv)
      return zr_raise_buf(zr_global(G_NO_METHOD_ERROR), b)
    end
    zr_class_allocate(recv)
  end

  # `Class#new`: allocate, then `initialize` with the arguments.
  #: (value, word, ptr, value, value) -> value
  def zr_class_new_instance(recv, argc, argv, cref, blk)
    o = zr_class_new_object(recv)
    return o if o == QUNDEF
    r = zr_send_blk(o, Machine.id(:initialize), argc, argv, blk)
    return r if r == QUNDEF
    o
  end

  # ruby's rb_class_new_instance for the core library: allocate, then the
  # program's `initialize` with the elements of `args`, with no frame for
  # `new`.
  #: (value, value) -> value
  def zr_class_new_program(klass, args)
    o = zr_class_new_object(klass)
    return o if o == QUNDEF
    r = zr_send_blk(o, Machine.id(:initialize), RArray[args].len, RArray[args].ptr, Machine.value(QNIL))
    return r if r == QUNDEF
    o
  end

  # `Array.new` and `String.new`: `Class#new` as a method entry of each
  # class, as CRuby defines them, so a backtrace from `initialize` includes
  # it.
  #: (value, word, ptr, value, value) -> value
  def zr_class_s_new(recv, argc, argv, cref, blk)
    zr_class_new_instance(recv, argc, argv, cref, blk)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_initialize(recv, argc, argv, cref, blk)
    Machine.value(QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_class(recv, argc, argv, cref, blk)
    zr_real_class(recv)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_singleton_class(recv, argc, argv, cref, blk)
    zr_singleton_class(recv)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_is_a(recv, argc, argv, cref, blk)
    k = Machine.value(Machine.load64(argv, 0))
    if !zr_module_p(k)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required"), 24)
    end
    zr_bool(zr_is_a(recv, k))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_of(recv, argc, argv, cref, blk)
    c = Machine.value(Machine.load64(argv, 0))
    if !zr_module_p(c)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required"), 24)
    end
    zr_bool(zr_real_class(recv) == c)
  end

  # `Object#eql?` compares identity. `Object#hash` returns a number from
  # the identity.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_eql_p(recv, argc, argv, cref, blk)
    zr_bool(recv == Machine.value(Machine.load64(argv, 0)))
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_hash(recv, argc, argv, cref, blk)
    # A fixnum hashes by its value, with the code that rb_hash and the
    # containers use for it, so `[1].hash` and an element whose hash is
    # `1.hash` agree.
    if zr_fixnum_p(recv)
      return zr_fix(zr_value_code(recv) & 4611686018427387903)
    end
    if !zr_special_p(recv) && RBasic[recv].klass == zr_global(G_INTEGER)
      return zr_big_hash(recv)
    end
    zr_fix(zr_obj_id_code(recv) & 4611686018427387903)
  end

  # Returns the hash code of a heap object, from its object_id, as CRuby's
  # objid_hash does. The first hash gives the object its id. An object's
  # code and id do not change, and a hash counts as an issued id.
  #: (value) -> word
  def zr_obj_id_code(obj)
    if zr_special_p(obj)
      return zr_hash_mix(Machine.word(obj))
    end
    zr_hash_mix(zr_fix2long(zr_obj_object_id(obj, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))))
  end

  # Returns a bignum's hash, from its sign and limbs, so equal bignums
  # have the same hash.
  #: (value) -> value
  def zr_big_hash(v)
    limbs = zr_hidden_get(v, zr_sym(Machine.id(:__limbs__)))
    h = zr_hidden_get(v, zr_sym(Machine.id(:__neg__))) == QTRUE ? 1 : 2
    i = 0
    while i < RArray[limbs].len
      h = zr_hash_mix(h ^ Machine.word(zr_ary_at(limbs, i)))
      i += 1
    end
    zr_fix(h & 4611686018427387903)
  end

  # `String#hash`: FNV-1a over the bytes with the process's seed. When the
  # bytes are not all ASCII, the encoding is also hashed, so two strings
  # that are not comparable have different codes.
  #: (value, word, ptr, value, value) -> value
  def zr_str_hash(recv, argc, argv, cref, blk)
    h = zr_str_bytes_hash(recv)
    if !zr_str_ascii_only(recv)
      h = Machine.mul_wrap(h ^ zr_str_encoding_index(recv), 1099511628211)
    end
    zr_fix(h & 4611686018427387903)
  end

  # `Object#send`: calls the method that the first argument gives, with
  # the other arguments.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_send(recv, argc, argv, cref, blk)
    if argc == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
    end
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    zr_send_blk(recv, Machine.load64(slot, 0), argc - 1, argv + 8, blk)
  end

  # `public_send`: the same as `send`, with visibility applied.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_public_send(recv, argc, argv, cref, blk)
    if argc == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
    end
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    if blk != QNIL
      RProc[blk].passed = 1
    end
    zr_dispatch(0, recv, Machine.load64(slot, 0), argc - 1, argv + 8, 3, blk)
  end

  # `Object#===`: the same as `==`.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_eqq(recv, argc, argv, cref, blk)
    # Identity first, then `==` as a truth value, as in CRuby's rb_equal.
    if recv == Machine.value(Machine.load64(argv, 0))
      return Machine.value(QTRUE)
    end
    # A receiver that uses BasicObject's `==` compares identity, with no
    # send. A `case` over symbols calls this for each branch that misses.
    if zr_key_builtin_p(recv, Machine.id(:==), Machine.addr(:zr_obj_eq))
      return Machine.value(QFALSE)
    end
    r = zr_send(recv, Machine.id(:==), 1, argv)
    return r if r == QUNDEF
    zr_bool(r != QNIL && r != QFALSE)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_nil_p(recv, argc, argv, cref, blk)
    zr_bool(recv == QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_eq(recv, argc, argv, cref, blk)
    zr_bool(recv == Machine.value(Machine.load64(argv, 0)))
  end

  # `!=` calls `==`, so a class that defines `==` also gets `!=`.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_ne(recv, argc, argv, cref, blk)
    r = zr_send(recv, Machine.id(:==), 1, argv)
    return r if r == QUNDEF
    zr_bool(r == QNIL || r == QFALSE)
  end

  # Returns the result of the receiver's own `respond_to_missing?(mid,
  # all)` as true or false, or undef when it raises.
  #: (value, word, value) -> value
  def zr_respond_to_missing(recv, mid, all)
    e = zr_find_method(zr_class_of(recv), Machine.id(:respond_to_missing?))
    if e == 0 || MEntry[e].fn == Machine.addr(:zr_obj_respond_to_missing)
      return Machine.value(QFALSE)
    end
    pair = Machine.slot(16)
    Machine.store64(pair, 0, Machine.word(zr_sym(mid)))
    Machine.store64(pair, 8, Machine.word(all))
    r = zr_invoke(e, recv, 2, pair, Machine.value(QNIL), 0)
    return r if r == QUNDEF
    zr_bool(r != QNIL && r != QFALSE)
  end

  # Whether the receiver's own `respond_to_missing?` returns true for
  # `mid`, called with include_all, as `defined?` and `method` call it.
  #: (value, word) -> bool
  def zr_respond_to_missing_p(recv, mid)
    zr_respond_to_missing(recv, mid, Machine.value(QTRUE)) == QTRUE
  end

  # `Object#respond_to_missing?`: false, for a subclass to override.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_respond_to_missing(recv, argc, argv, cref, blk)
    if argc != 2
      return zr_wrong_arity(argc, 2)
    end
    Machine.value(QFALSE)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_respond_to(recv, argc, argv, cref, blk)
    if argc < 1 || argc > 2
      return zr_wrong_arity_range(argc, 1, 2)
    end
    m = Machine.value(Machine.load64(argv, 0))
    if !zr_special_p(m) && zr_type(m) == T_STRING
      m = zr_sym(zr_intern(RString[m].ptr, RString[m].len))
    end
    unless zr_symbol_p(m)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      s = zr_inspect(m)
      return s if s == QUNDEF
      zr_buf_str(b, s)
      zr_buf_push(b, Machine.bytes(" is not a symbol nor a string"), 29)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    all = argc == 2 && Machine.value(Machine.load64(argv, 8)) != QNIL && Machine.value(Machine.load64(argv, 8)) != QFALSE
    e = zr_find_method(zr_box_view(zr_class_of(recv)), zr_sym2id(m))
    if e == 0 || zr_entry_hidden_p(e)
      return zr_respond_to_missing(recv, zr_sym2id(m), zr_bool(all))
    end
    if MEntry[e].fn == Machine.addr(:zr_f_notimplement)
      return Machine.value(QFALSE)
    end
    if all || MEntry[e].vis == VIS_PUBLIC
      return Machine.value(QTRUE)
    end
    # method_boundp finds no public method, so respond_to_missing? answers.
    zr_respond_to_missing(recv, zr_sym2id(m), Machine.value(QFALSE))
  end

  # Writes `#<Name:0x...` with sixteen hex digits into `b`.
  #: (ptr, value) -> void
  def zr_buf_obj_head(b, obj)
    zr_buf_push(b, Machine.bytes("#<"), 2)
    zr_buf_class_of(b, obj)
    zr_buf_push(b, Machine.bytes(":0x"), 3)
    w = Machine.word(obj)
    i = 0
    while i < 16
      d = (w >> (60 - (i * 4))) & 15
      if d < 10
        zr_buf_byte(b, 48 + d)
      else
        zr_buf_byte(b, 87 + d)
      end
      i += 1
    end
  end

  # Returns a class's path, as rb_class_path does: its name, or
  # `#<Class:0x...>` (`#<Module:0x...>`) when it has no name. It runs no
  # Ruby, so any message can include any class.
  #: (value) -> value
  def zr_class_path(klass)
    if RClass[klass].name != QNIL
      return RClass[klass].name
    end
    zr_any_to_s(klass)
  end

  # Writes the path of `v`'s class into `b`, as a message shows it.
  #: (ptr, value) -> void
  def zr_buf_class_of(b, v)
    zr_buf_str(b, zr_class_name_of(v))
  end

  # `#<Name:0x...>`, rb_any_to_s.
  #: (value) -> value
  def zr_any_to_s(v)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, v)
    zr_buf_byte(b, 62)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # Returns an object's `#<...>` form, as the core library's C code writes
  # it, in a String that starts as binary (rb_str_buf_new). It stays
  # binary while the text is plain ASCII. Otherwise it gets the encoding
  # of the first non-ASCII piece.
  #: (value) -> value
  def zr_obj_form(text)
    if !zr_str_ascii_bytes_p(text)
      return text
    end
    if zr_frozen_p(text)
      text = zr_str_new(RString[text].ptr, RString[text].len)
    end
    zr_str_set_index(text, ENC_BINARY)
  end

  # vm_objtostring under refinements: a String or a Symbol goes into an
  # interpolation as it is, whatever `to_s` a refinement gives it. Any other
  # part gets the refined `to_s`.
  #: (value) -> bool
  def zr_interp_plain_p(v)
    if zr_symbol_p(v)
      return true
    end
    !zr_special_p(v) && (zr_type(v) == T_STRING || zr_type(v) == T_SYMBOL)
  end

  # rb_obj_as_string: returns a String unchanged, else the result of
  # `to_s`. When that is also not a String, it returns `v` as rb_any_to_s
  # writes it. Returns undef when `to_s` raised.
  #: (value) -> value
  def zr_obj_as_string(v)
    if !zr_special_p(v) && (RBasic[v].flags & T_MASK) == T_STRING
      return v
    end
    s = zr_send(v, Machine.id(:to_s), 0, 0)
    return s if s == QUNDEF
    if !zr_special_p(s) && (RBasic[s].flags & T_MASK) == T_STRING
      return s
    end
    zr_any_to_s(v)
  end

  # rb_inspect: the result of `inspect`, made a String by
  # rb_obj_as_string. Non-ASCII text in an encoding other than UTF-8 (the
  # default external encoding) is escaped, so all results are compatible
  # with each other. Returns undef when one of these calls raised.
  #: (value) -> value
  def zr_inspect(v)
    s = zr_send(v, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    s = zr_obj_as_string(s)
    return s if s == QUNDEF
    if zr_str_encoding_index(s) == ENC_UTF8 || zr_str_ascii_bytes_p(s)
      return s
    end
    zr_send(s, Machine.id(:escape), 0, 0)
  end

  # `#<Name:0x... @a=1, @b=2>`. The `inspect` of an ivar value can run
  # Ruby, so the table is read again after each one.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_inspect(recv, argc, argv, cref, blk)
    # As in rb_obj_inspect, only a plain object shows its instance
    # variables. All others (for example a fixnum, when a redefined
    # Integer#inspect calls super) use the address form.
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, recv)
    if zr_special_p(recv) || zr_type(recv) != T_OBJECT
      zr_buf_byte(b, 62)
      return zr_buf_take_at(b, ENC_BINARY)
    end
    filter = zr_send(recv, Machine.id(:instance_variables_to_inspect), 0, 0)
    if filter == QUNDEF
      zr_buf_free(b)
      return filter
    end
    if filter != QNIL && (zr_special_p(filter) || zr_type(filter) != T_ARRAY)
      zr_buf_free(b)
      m = Machine.slot(Buf.size)
      zr_buf_init(m)
      zr_buf_push(m, Machine.bytes("Expected #instance_variables_to_inspect to return an Array or nil, but it returned "), 83)
      zr_buf_class_of(m, filter)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), m)
    end
    # An object found again inside its own inspect shows ` ...` in place
    # of its instance variables (rb_exec_recursive).
    if zr_guard_enter(recv, Machine.id(:inspect))
      zr_buf_push(b, Machine.bytes(" ...>"), 5)
      return zr_buf_take_at(b, ENC_BINARY)
    end
    r = zr_buf_ivars(b, recv, filter)
    zr_guard_leave(recv, Machine.id(:inspect))
    if r == QUNDEF
      zr_buf_free(b)
      return r
    end
    zr_buf_byte(b, 62)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # Writes ` @a=1, @b=2` into `b`: the visible instance variables that
  # `filter` accepts (nil accepts all), each value inspected. Returns undef
  # when an inspect raised.
  #: (ptr, value, value) -> value
  def zr_buf_ivars(b, recv, filter)
    i = 0
    shown = 0
    while i < RObject[recv].iv.len
      e = RObject[recv].iv.rows + (i * IvEntry.size)
      i += 1
      if zr_ivar_id_visible_p(IvEntry[e].id) && (filter == QNIL || zr_ary_index_of(filter, zr_sym(IvEntry[e].id)) >= 0)
        zr_buf_push(b, shown == 0 ? Machine.bytes(" ") : Machine.bytes(", "), shown == 0 ? 1 : 2)
        shown += 1
        zr_buf_sym(b, IvEntry[e].id)
        zr_buf_byte(b, 61)
        s = zr_inspect(IvEntry[e].value)
        return s if s == QUNDEF
        zr_buf_str(b, s)
      end
    end
    Machine.value(QNIL)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_nil_inspect(recv, argc, argv, cref, blk)
    zr_usascii_str_new(Machine.bytes("nil"), 3)
  end

  #: (word) -> bool
  def zr_ident_byte_p(c)
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c >= 128
  end

  # Whether `c` is a punctuation mark that ruby accepts as a global name.
  #: (word) -> bool
  def zr_gvar_punct_p(c)
    c == 126 || c == 42 || c == 36 || c == 63 || c == 33 || c == 64 || c == 47 || c == 92 || c == 59 || c == 44 || c == 46 || c == 61 || c == 58 || c == 60 || c == 62 || c == 34 || c == 38 || c == 96 || c == 39 || c == 43 || c == 48
  end

  # Whether the part after the `$` is a special global name: one
  # punctuation mark, a `-` and one character, or only digits.
  #: (ptr, word) -> bool
  def zr_special_gvar_p(p, n)
    if n == 0
      return false
    end
    c = Machine.u8(Machine.load8(p, 0))
    if zr_gvar_punct_p(c)
      return n == 1
    end
    if c == 45
      if n == 1
        return false
      end
      d = Machine.u8(Machine.load8(p, 1))
      len = 1
      if d >= 128
        len = zr_utf8_char_len(p + 1, n - 1)
        if len == 0
          return false
        end
      elsif !zr_ident_byte_p(d)
        return false
      end
      return n == 1 + len
    end
    i = 0
    while i < n
      d = Machine.u8(Machine.load8(p + i, 0))
      if d < 48 || d > 57
        return false
      end
      i += 1
    end
    true
  end

  # Whether `n` bytes are a plain name for a symbol literal: an identifier
  # that can end in `?`, `!` or `=`, an identifier with a `@`, `@@` or `$`
  # sigil (then without the suffix), or an operator.
  #: (ptr, word) -> bool
  def zr_symname_plain_p(p, n)
    if n == 0
      return false
    end
    c = Machine.u8(Machine.load8(p, 0))
    i = 0
    if c == 64
      i = 1
      if n > 1 && Machine.u8(Machine.load8(p, 1)) == 64
        i = 2
      end
    elsif c == 36
      if zr_special_gvar_p(p + 1, n - 1)
        return true
      end
      i = 1
    end
    if i > 0
      if i >= n
        return false
      end
      first = Machine.u8(Machine.load8(p + i, 0))
      if first >= 48 && first <= 57
        return false
      end
      while i < n
        if !zr_ident_byte_p(Machine.u8(Machine.load8(p + i, 0)))
          return false
        end
        i += 1
      end
      return true
    end
    if c >= 48 && c <= 57
      return false
    end
    if !zr_ident_byte_p(c)
      return zr_operator_name_p(p, n)
    end
    while i < n
      c = Machine.u8(Machine.load8(p + i, 0))
      if !zr_ident_byte_p(c)
        return i == n - 1 && (c == 63 || c == 33 || c == 61)
      end
      i += 1
    end
    true
  end

  # `:name`, with quotes when the name is not a plain identifier or
  # operator. A name that is not UTF-8 contains non-ASCII bytes, so it is
  # quoted with those bytes in hex.
  #: (value, word, ptr, value, value) -> value
  def zr_sym_inspect(recv, argc, argv, cref, blk)
    id = zr_sym2id(recv)
    # A name with a non-ASCII character is shown or escaped by that
    # character's category, and that table is in Ruby. The Ruby code calls
    # back here for a name that needs no escape.
    if zr_symbol_tag(id) == 0 && !zr_bytes_ascii_only_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
      return zr_send(recv, Machine.id(:utf8_inspect), 0, 0)
    end
    zr_sym_inspect_bytes(recv)
  end

  # Whether each byte in a run is ASCII. Call it before any allocation, so
  # the run's pointer cannot move first.
  #: (ptr, word) -> bool
  def zr_bytes_ascii_only_p(p, n)
    i = 0
    while i < n
      if Machine.u8(Machine.load8(p + i, 0)) >= 128
        return false
      end
      i += 1
    end
    true
  end

  # Returns the name as the runtime writes it: bare for a plain name, and
  # quoted with escapes for all others.
  #: (value) -> value
  def zr_sym_inspect_bytes(sym)
    id = zr_sym2id(sym)
    p = zr_symbol_name_ptr(id)
    n = zr_symbol_name_len(id)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, 58)
    if zr_symbol_tag(id) == 0 && zr_symname_plain_p(p, n)
      zr_buf_push(b, p, n)
      # A plain name keeps the symbol's encoding: US-ASCII for plain ASCII.
      return zr_buf_take_at(b, ENC_USASCII)
    end
    # A plain ASCII name is US-ASCII, and escapes a control byte in hex.
    zr_buf_str_escaped(b, p, n, zr_symbol_tag(id) != 0 || zr_bytes_ascii_only_p(p, n))
    zr_buf_take(b)
  end

  #: (ptr, word) -> bool
  def zr_operator_name_p(p, n)
    if n == 1
      c = Machine.u8(Machine.load8(p, 0))
      c == 43 || c == 45 || c == 42 || c == 47 || c == 37 || c == 60 || c == 62 || c == 33 || c == 38 || c == 124 || c == 94 || c == 126 || c == 96
    elsif n == 2
      c = Machine.u8(Machine.load8(p, 0))
      d = Machine.u8(Machine.load8(p, 1))
      (c == 60 && (d == 60 || d == 61)) || (c == 62 && (d == 62 || d == 61)) || (c == 61 && (d == 61 || d == 126)) || (c == 33 && (d == 61 || d == 126)) || (c == 42 && d == 42) || (c == 91 && d == 93) || ((c == 43 || c == 45) && d == 64)
    elsif n == 3
      c = Machine.u8(Machine.load8(p, 0))
      d = Machine.u8(Machine.load8(p, 1))
      e = Machine.u8(Machine.load8(p, 2))
      (c == 60 && d == 61 && e == 62) || (c == 61 && d == 61 && e == 61) || (c == 91 && d == 93 && e == 61)
    else
      false
    end
  end

  # Returns the length of the valid UTF-8 sequence at `p`, or 0 when the
  # byte does not start one.
  #: (ptr, word) -> word
  def zr_utf8_char_len(p, n)
    c = Machine.u8(Machine.load8(p, 0))
    if c < 128
      return 1
    end
    len = 0
    if c >= 194 && c <= 223
      len = 2
    elsif c >= 224 && c <= 239
      len = 3
    elsif c >= 240 && c <= 244
      len = 4
    end
    if len == 0 || len > n
      return 0
    end
    # After four lead bytes, the second byte's range is smaller, as in
    # enc/utf_8.c: no overlong form, no surrogate, nothing past U+10FFFF.
    low = 128
    high = 191
    if c == 224
      low = 160
    elsif c == 237
      high = 159
    elsif c == 240
      low = 144
    elsif c == 244
      high = 143
    end
    d = Machine.u8(Machine.load8(p + 1, 0))
    if d < low || d > high
      return 0
    end
    i = 2
    while i < len
      d = Machine.u8(Machine.load8(p + i, 0))
      if d < 128 || d > 191
        return 0
      end
      i += 1
    end
    len
  end

  # Writes `n` bytes double-quoted and escaped, as String#inspect does. A
  # binary string writes each high byte in hex. A text string keeps a
  # valid UTF-8 character and writes all other bytes in hex.
  #: (ptr, ptr, word, bool) -> void
  def zr_buf_str_escaped(b, p, n, binary)
    zr_buf_byte(b, 34)
    i = 0
    while i < n
      c = Machine.u8(Machine.load8(p + i, 0))
      if c >= 128
        len = binary ? 0 : zr_utf8_char_len(p + i, n - i)
        if len == 0
          zr_buf_push(b, Machine.bytes("\\x"), 2)
          zr_buf_byte(b, zr_hex_digit(c >> 4))
          zr_buf_byte(b, zr_hex_digit(c & 15))
          i += 1
        else
          zr_buf_push(b, p + i, len)
          i += len
        end
      elsif c == 34 || c == 92
        zr_buf_byte(b, 92)
        zr_buf_byte(b, c)
      elsif c == 10
        zr_buf_push(b, Machine.bytes("\\n"), 2)
      elsif c == 9
        zr_buf_push(b, Machine.bytes("\\t"), 2)
      elsif c == 13
        zr_buf_push(b, Machine.bytes("\\r"), 2)
      elsif c == 27
        zr_buf_push(b, Machine.bytes("\\e"), 2)
      elsif c == 7
        zr_buf_push(b, Machine.bytes("\\a"), 2)
      elsif c == 8
        zr_buf_push(b, Machine.bytes("\\b"), 2)
      elsif c == 12
        zr_buf_push(b, Machine.bytes("\\f"), 2)
      elsif c == 11
        zr_buf_push(b, Machine.bytes("\\v"), 2)
      elsif c == 35 && i + 1 < n && (Machine.u8(Machine.load8(p + i, 1)) == 123 || Machine.u8(Machine.load8(p + i, 1)) == 36 || Machine.u8(Machine.load8(p + i, 1)) == 64)
        zr_buf_push(b, Machine.bytes("\\#"), 2)
      elsif c < 32 || c == 127
        zr_buf_push(b, binary ? Machine.bytes("\\x") : Machine.bytes("\\u00"), binary ? 2 : 4)
        zr_buf_byte(b, zr_hex_digit(c >> 4))
        zr_buf_byte(b, zr_hex_digit(c & 15))
      else
        zr_buf_byte(b, c)
      end
      i += 1 if c < 128
    end
    zr_buf_byte(b, 34)
  end

  #: (word) -> word
  def zr_hex_digit(d)
    if d < 10
      48 + d
    else
      55 + d
    end
  end

  # rb_str_inspect returns its text in default_internal, else in
  # default_external, else in US-ASCII when that is not ASCII-compatible.
  # Then no character prints as itself, and the result is US-ASCII.
  #: (value, word, ptr, value, value) -> value
  def zr_str_inspect(recv, argc, argv, cref, blk)
    r = zr_str_inspect_text(recv)
    if r != QUNDEF && zr_inspect_usascii_p() && zr_str_ascii_only(r)
      zr_str_set_index(r, ENC_USASCII)
    end
    r
  end

  #: () -> bool
  def zr_inspect_usascii_p
    Machine.load64(Machine.static(:inspect_usascii, 8), 0) != 0
  end

  #: () -> value
  def zr_inspect_usascii_m
    zr_bool(zr_inspect_usascii_p())
  end

  # Set by Encoding.default_external= and default_internal=.
  #: (value) -> value
  def zr_inspect_usascii_set(flag)
    Machine.store64(Machine.static(:inspect_usascii, 8), 0, flag == QTRUE ? 1 : 0)
    flag
  end

  #: (value) -> value
  def zr_str_inspect_text(recv)
    # UTF-16 and UTF-32 inspect by characters, and their dummy encodings by
    # bytes. That code is in Ruby.
    index = zr_str_encoding_index(recv)
    if !zr_enc_ascii_compat_p(index)
      return zr_send(recv, Machine.id(:unit_inspect), 0, 0)
    end
    # A multibyte encoding's characters are not Unicode code points, so
    # each one prints as the number of its own bytes. That code is in Ruby.
    if zr_enc_mb_p(index)
      return zr_send(recv, Machine.id(:mb_inspect), 0, 0)
    end
    # A non-ASCII character is shown or escaped by its category, and the
    # table of those categories is in Ruby.
    if zr_str_wide_p(recv) && !zr_str_ascii_only(recv)
      return zr_send(recv, Machine.id(:utf8_inspect), 0, 0)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_str_escaped(b, RString[recv].ptr, RString[recv].len, !zr_str_wide_p(recv))
    zr_buf_take(b)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_true_inspect(recv, argc, argv, cref, blk)
    zr_true_to_s(recv, argc, argv, cref, blk)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_false_inspect(recv, argc, argv, cref, blk)
    zr_false_to_s(recv, argc, argv, cref, blk)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_class_name(recv, argc, argv, cref, blk)
    RClass[recv].name
  end

  # Writes a class's name in a message, or its `#<Class:0x...>` form when
  # it has no name. Returns QUNDEF when an inspect raised.
  #: (ptr, value) -> value
  def zr_buf_class(b, klass)
    if RClass[klass].name != QNIL && !zr_singleton_p(klass)
      zr_buf_str(b, RClass[klass].name)
      return Machine.value(QNIL)
    end
    s = zr_class_to_s(klass, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
    return s if s == QUNDEF
    zr_buf_str(b, s)
    Machine.value(QNIL)
  end

  # An anonymous class prints as `#<Class:0x...>`. A singleton class
  # prints as `#<Class:` around the object that it is attached to.
  #: (value, word, ptr, value, value) -> value
  def zr_class_to_s(recv, argc, argv, cref, blk)
    refined = ClassExt[RClass[recv].ext].refined
    if refined != QNIL
      inner = zr_send(refined, Machine.id(:to_s), 0, 0)
      return inner if inner == QUNDEF
      origin = zr_send(zr_ivar_get(recv, Machine.id(:__origin__)), Machine.id(:to_s), 0, 0)
      return origin if origin == QUNDEF
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("#<refinement:"), 13)
      zr_buf_str(b, inner)
      zr_buf_byte(b, 64)
      zr_buf_str(b, origin)
      zr_buf_byte(b, 62)
      return zr_buf_take_at(b, ENC_USASCII)
    end
    if zr_singleton_p(recv)
      # rb_mod_to_s inspects a class or a module, and shows any other
      # object by its address.
      attached = RClass[recv].attached
      if !zr_special_p(attached) && (zr_type(attached) == T_CLASS || zr_type(attached) == T_MODULE)
        inner = zr_inspect(attached)
      else
        inner = zr_any_to_s(attached)
      end
      return inner if inner == QUNDEF
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("#<Class:"), 8)
      zr_buf_str(b, inner)
      zr_buf_byte(b, 62)
      return zr_buf_take_at(b, ENC_USASCII)
    end
    if RClass[recv].name == QNIL
      return zr_any_to_s(recv)
    end
    # The class's name is frozen, so `to_s` returns a copy of it.
    name = RClass[recv].name
    zr_str_copy_encoding(zr_str_new(RString[name].ptr, RString[name].len), name)
  end

  # Returns the superclass, after the proxies of included modules.
  #: (value) -> value
  def zr_real_superclass(klass)
    k = RClass[klass].superclass
    while k != QNIL && zr_type(k) == T_ICLASS
      k = RClass[k].superclass
    end
    k
  end

  #: (value, word, ptr, value, value) -> value
  def zr_class_superclass(recv, argc, argv, cref, blk)
    # A class from `Class.allocate` has no superclass until it is set up.
    if RClass[recv].superclass == QNIL && recv != zr_global(G_BASIC_OBJECT)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("uninitialized class"), 19)
    end
    zr_real_superclass(recv)
  end

  # `Exception#to_s`: the message, or the class name when there is no
  # message. A message that is not a String goes through `to_s`.
  #: (value) -> value
  def zr_exc_to_s(recv)
    m = RException[recv].message
    # A new copy of the class's name, as rb_class_name gives, because the
    # caller can change the message that it gets.
    if m == QNIL
      name = zr_class_name_of(recv)
      return zr_str_new_at(RString[name].ptr, RString[name].len, zr_str_encoding_index(name))
    end
    if zr_special_p(m) || zr_type(m) != T_STRING
      return zr_send(m, Machine.id(:to_s), 0, 0)
    end
    m
  end

  # Returns the message as it was given, or nil when the class name is in
  # place of it. Marshal must know the difference.
  #: (value) -> value
  def zr_exc_raw_message(recv)
    RException[recv].message
  end

  #: (value, value) -> value
  def zr_exc_set_message(recv, m)
    RException[recv].message = m
    m
  end

  # `#<Klass: to_s>`, or only the class name when `to_s` is empty. A
  # message with a newline is shown inspected.
  #: (value, word, ptr, value, value) -> value
  def zr_exc_inspect(recv, argc, argv, cref, blk)
    m = zr_send(recv, Machine.id(:to_s), 0, 0)
    return m if m == QUNDEF
    if zr_special_p(m) || zr_type(m) != T_STRING
      m = zr_send(m, Machine.id(:to_s), 0, 0)
      return m if m == QUNDEF
    end
    if RString[m].len == 0
      return zr_class_name_of(recv)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("#<"), 2)
    zr_buf_class_of(b, recv)
    if zr_bytes_index(RString[m].ptr, RString[m].len, 10) >= 0
      zr_buf_byte(b, 58)
      zr_buf_str_escaped(b, RString[m].ptr, RString[m].len, !zr_str_wide_p(m))
    else
      zr_buf_push(b, Machine.bytes(": "), 2)
      zr_buf_str(b, m)
    end
    zr_buf_byte(b, 62)
    zr_buf_take_at(b, ENC_BINARY)
  end

  # Returns the index of the byte `c` in `n` bytes at `p`, or -1.
  #: (ptr, word, word) -> word
  def zr_bytes_index(p, n, c)
    i = 0
    while i < n
      if Machine.u8(Machine.load8(p + i, 0)) == c
        return i
      end
      i += 1
    end
    0 - 1
  end

  #: (value, word, ptr, value, value) -> value
  def zr_exc_initialize(recv, argc, argv, cref, blk)
    if argc > 1
      return zr_wrong_arity_range(argc, 0, 1)
    end
    if argc > 0
      RException[recv].message = Machine.value(Machine.load64(argv, 0))
    end
    Machine.value(QNIL)
  end

  # `p`: writes each argument's inspect on its own line. Returns the
  # argument, or an Array of the arguments when there are several.
  #: (value, word, ptr, value, value) -> value
  def zr_p(recv, argc, argv, cref, blk)
    i = 0
    while i < argc
      s = zr_inspect(Machine.value(Machine.load64(argv + (i * 8), 0)))
      return s if s == QUNDEF
      zr_write_out(RString[s].ptr, RString[s].len)
      zr_write_out(Machine.bytes("\n"), 1)
      i += 1
    end
    if argc == 0
      return Machine.value(QNIL)
    end
    if argc > 1
      return zr_ary_of(argc, argv)
    end
    Machine.value(Machine.load64(argv, 0))
  end

  # Returns a FrameMeta for the current position of the frame `rec`: the
  # file and line where an attribute is declared.
  #: (ptr) -> ptr
  def zr_meta_at(rec)
    from = Frame[rec].meta
    meta = zr_meta_new()
    FrameMeta[meta].file = FrameMeta[from].file
    FrameMeta[meta].file_len = FrameMeta[from].file_len
    FrameMeta[meta].line = zr_frame_line(rec)
    FrameMeta[meta].node = zr_frame_node_id(rec)
    meta
  end

  # `attr_reader`, `attr_writer`, `attr_accessor`: one method entry for
  # each name, with the class body's current visibility. Returns the
  # defined names.
  #: (value, word, ptr, word) -> value
  def zr_attr(klass, argc, argv, which)
    defined = zr_ary_new(argc * 2)
    i = 0
    while i < argc
      slot = Machine.slot(8)
      r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
      return r if r == QUNDEF
      id = Machine.load64(slot, 0)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      unless zr_ident_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
        zr_buf_push(b, Machine.bytes("invalid attribute name '"), 24)
        zr_buf_sym(b, id)
        zr_buf_byte(b, 39)
        exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
        zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
        zr_exc_detail(exc, Machine.id(:receiver), klass)
        return zr_raise(exc)
      end
      zr_buf_byte(b, 64)
      zr_buf_sym(b, id)
      ivar = zr_intern(Buf[b].ptr, Buf[b].len)
      caller = Frame[Task[zr_task()].top].prev
      # The runtime's own attributes, which its class bodies define on
      # themselves, read hidden fields: the runtime keeps these instance
      # variables without the `@`. A call that a builtin makes for the
      # program, as in `each(&method(:attr_reader))`, is the program's call.
      if zr_internal_meta_p(zr_meta_at(caller)) && Frame[caller].self == klass
        ivar = zr_intern(Buf[b].ptr + 1, Buf[b].len - 1)
      end
      # The scope's visibility keyword applies only inside this class's own
      # body, or a block that runs with the class as self and definee (as
      # `Class.new { }` runs). From any other place, the attribute is public.
      cref = zr_cref_in_context(caller, klass)
      if cref == QNIL
        cref = Frame[caller].cref
        if cref != QNIL && zr_cref_klass(zr_cref_lexical(cref)) != klass
          cref = Machine.value(QNIL)
        end
      end
      if which != 2
        r = zr_define_method(klass, id, Machine.ptr(ivar), 0, KIND_ATTR_READER, zr_meta_at(caller), cref)
        if r == QUNDEF
          zr_buf_free(b)
          return r
        end
        zr_ary_push(defined, zr_sym(id))
      end
      if which != 1
        zr_buf_byte(b, 61)
        setter = zr_intern(Buf[b].ptr + 1, Buf[b].len - 1)
        r = zr_define_method(klass, setter, Machine.ptr(ivar), 1, KIND_ATTR_WRITER, zr_meta_at(caller), cref)
        if r == QUNDEF
          zr_buf_free(b)
          return r
        end
        zr_ary_push(defined, zr_sym(setter))
      end
      zr_buf_free(b)
      i += 1
    end
    defined
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_attr_reader(recv, argc, argv, cref, blk)
    zr_attr(recv, argc, argv, 1)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_attr_writer(recv, argc, argv, cref, blk)
    zr_attr(recv, argc, argv, 2)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_attr_accessor(recv, argc, argv, cref, blk)
    zr_attr(recv, argc, argv, 3)
  end

  # `attr`: attr_reader, but for the old form `attr name, true` (an
  # accessor) or `attr name, false` (a reader), as rb_mod_attr reads it.
  # Its warning is in the deprecated category, which is off by default.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_attr(recv, argc, argv, cref, blk)
    if argc == 2
      flag = Machine.value(Machine.load64(argv, 8))
      if flag == QTRUE || flag == QFALSE
        if zr_send(zr_global(G_KERNEL), Machine.id(:obsolete_attr_flag), 0, 0) == QUNDEF
          return Machine.value(QUNDEF)
        end
        return zr_attr(recv, 1, argv, flag == QTRUE ? 3 : 1)
      end
    end
    zr_attr(recv, argc, argv, 1)
  end

  # Continues `dig` into `v` with `rest`. CRuby's rb_obj_dig continues only
  # into an Array, Hash, Struct or an object with a public `dig`.
  #: (value, value) -> value
  def zr_dig_into(v, rest)
    klass = zr_class_of(v)
    e = zr_find_method(klass, Machine.id(:dig))
    if e == 0 || MEntry[e].vis != VIS_PUBLIC
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_class_of(b, v)
      zr_buf_push(b, Machine.bytes(" does not have #dig method"), 26)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    zr_send(v, Machine.id(:dig), RArray[rest].len, RArray[rest].ptr)
  end

  # How the core library's own `a == b` answers where CRuby's C compares
  # natively, whatever a program redefines: 1 when equal, 2 when not, and
  # 0 when it sends `==`. A Symbol, nil, true or false compares by
  # identity, and a plain String with a String by its bytes.
  #: (value, value) -> word
  def zr_native_eq_kind(a, b)
    if zr_symbol_p(a) || a == QNIL || a == QTRUE || a == QFALSE
      return a == b ? 1 : 2
    end
    if !zr_special_p(a) && !zr_special_p(b) && RBasic[a].klass == zr_global(G_STRING) && zr_type(b) == T_STRING
      same = zr_bytes_eq(RString[a].ptr, RString[a].len, RString[b].ptr, RString[b].len) && zr_str_comparable(a, b)
      return same ? 1 : 2
    end
    0
  end

  # The core library's own `x.between?(low, high)`: three fixnums compare
  # natively, as CRuby's C checks a range. Anything else sends between?.
  #: (value, ptr) -> value
  def zr_native_between(x, argv)
    low = Machine.value(Machine.load64(argv, 0))
    high = Machine.value(Machine.load64(argv, 8))
    if zr_fixnum_p(x) && zr_fixnum_p(low) && zr_fixnum_p(high)
      n = zr_fix2long(x)
      return zr_bool(n >= zr_fix2long(low) && n <= zr_fix2long(high))
    end
    zr_send(x, Machine.id(:between?), 2, argv)
  end

  # Whether one of the core library's own tables (an Array) holds `x`, as
  # CRuby's C finds it with a switch or strcmp: identity, a String by its
  # bytes, and rb_equal for anything else. Thus a program that redefines
  # Integer#== or String#== sees no call from the lookup.
  #: (value, value) -> value
  def zr_table_member_p(ary, x)
    i = 0
    while i < RArray[ary].len
      e = zr_ary_at(ary, i)
      if e == x
        return Machine.value(QTRUE)
      end
      if !zr_special_p(e) && !zr_special_p(x) && zr_type(e) == T_STRING && zr_type(x) == T_STRING
        if zr_bytes_eq(RString[e].ptr, RString[e].len, RString[x].ptr, RString[x].len) && zr_str_comparable(e, x)
          return Machine.value(QTRUE)
        end
      elsif !zr_special_p(e) && zr_type(e) != T_STRING
        r = zr_rb_equal(e, x)
        if r != QFALSE
          return r
        end
      end
      i += 1
    end
    Machine.value(QFALSE)
  end

  # CRuby's rb_eql, which Array#-, Array#& and Array#eql? compare with:
  # identity, then the answer without a send where rb_eql_opt has one (the
  # same rule as for `==`, which rb_eql_opt reads), then `eql?`.
  #: (value, value) -> value
  def zr_rb_eql(a, b)
    if a == b
      return Machine.value(QTRUE)
    end
    if zr_fixnum_p(a) && zr_fixnum_p(b) && (Machine.gates & GATE_EQ) == 0
      return Machine.value(QFALSE)
    end
    if zr_flonum_p(a) && zr_flonum_p(b) && (Machine.gates & GATE_FLO_EQ) == 0
      return Machine.value(QFALSE)
    end
    if zr_key_builtin_p(a, Machine.id(:eql?), Machine.addr(:zr_obj_eql_p))
      return Machine.value(QFALSE)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(b))
    r = zr_send(a, Machine.id(:eql?), 1, slot)
    return r if r == QUNDEF
    (r == QNIL || r == QFALSE) ? Machine.value(QFALSE) : Machine.value(QTRUE)
  end

  # CRuby's rb_equal: an object is equal to itself, with no call of `==`.
  # All containers compare their elements this way. That is why
  # `[nan].include?(nan)` is true while `nan == nan` is false.
  #: (value, value) -> value
  def zr_rb_equal(a, b)
    if a == b
      return Machine.value(QTRUE)
    end
    # Two different fixnums or flonums while their class's `==` is ruby's
    # own, or a receiver that uses BasicObject's `==` (a Symbol, an
    # Object), are not equal, with no send (opt_equality_specialized).
    if zr_fixnum_p(a) && zr_fixnum_p(b) && (Machine.gates & GATE_EQ) == 0
      return Machine.value(QFALSE)
    end
    if zr_flonum_p(a) && zr_flonum_p(b) && (Machine.gates & GATE_FLO_EQ) == 0
      return Machine.value(QFALSE)
    end
    if zr_key_builtin_p(a, Machine.id(:==), Machine.addr(:zr_obj_eq))
      return Machine.value(QFALSE)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(b))
    r = zr_send(a, Machine.id(:==), 1, slot)
    return r if r == QUNDEF
    (r == QNIL || r == QFALSE) ? Machine.value(QFALSE) : Machine.value(QTRUE)
  end
end
