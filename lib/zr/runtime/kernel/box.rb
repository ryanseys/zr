module Zr::Kern
  # Ruby::Box. A box is a module that represents its own view of the
  # program state. When a box patches a class, the class gets a SHADOW: a
  # separate class whose superclass is the shared class. Each lookup in
  # the box reads the shadow first. The toplevel constants and globals
  # that a box writes belong to the box. Of main's state, a box reads only
  # what the runtime contained when the program started.
  G_MASTER_GVARS = 48
  G_BOX = 49

  # The Ruby::Box class, which the core library sets here.
  #: (value) -> value
  def zr_box_register(klass)
    zr_set_global(G_BOX, klass)
    Machine.value(QNIL)
  end

  # Whether `scope` is a toplevel: Object, or a box, which has its own
  # toplevel constants. A class set there gets its plain name, as for a
  # class set on Object.
  #: (value) -> bool
  def zr_toplevel_scope_p(scope)
    if scope == zr_global(G_OBJECT)
      return true
    end
    box = zr_global(G_BOX)
    !zr_special_p(box) && zr_real_class(scope) == box
  end

  # The box of the running code, which is the box where its FUNCTION was
  # written. Code that is part of the runtime belongs to main, even when a
  # box calls it.
  #: () -> value
  def zr_box_current
    t = Task[zr_task()].top
    if t == 0
      return Machine.value(QNIL)
    end
    m = Frame[t].meta
    if m == 0
      return Machine.value(QNIL)
    end
    b = FrameMeta[m].box
    Machine.word(b) == 0 ? Machine.value(QNIL) : b
  end

  # The box that a call COMES from. A builtin runs inside its caller, as a
  # C method does, so the frame walk skips all builtins.
  #: () -> value
  def zr_box_reach
    f = Task[zr_task()].top
    while f != 0
      m = Frame[f].meta
      if m == 0
        return Machine.value(QNIL)
      end
      if FrameMeta[m].kind != KIND_BUILTIN && FrameMeta[m].kind != KIND_HIDDEN
        b = FrameMeta[m].box
        return Machine.word(b) == 0 ? Machine.value(QNIL) : b
      end
      f = Frame[f].prev
    end
    Machine.value(QNIL)
  end

  # The snippet's toplevel shows its own label in a backtrace.
  #: (value) -> value
  def zr_box_compiled(meta)
    FrameMeta[Machine.ptr(zr_fix2long(meta))].kind = KIND_COMPILED
    Machine.value(QNIL)
  end

  # Each function of a box's own unit refers to the box. Thus the box
  # applies to its own code and to nothing else. A constant cache entry
  # filled before the code had a box is not valid after this.
  #: (value, value) -> value
  def zr_box_stamp(metas, b)
    i = 0
    while i < RArray[metas].len
      FrameMeta[Machine.ptr(zr_fix2long(zr_ary_at(metas, i)))].box = b
      i += 1
    end
    zr_consts_changed()
    Machine.value(QNIL)
  end

  # The slot of the next box. It is the index into the shadow list that
  # each class keeps.
  #: () -> value
  def zr_box_slot
    c = Machine.static(:box_slots, 8)
    n = Machine.load64(c, 0)
    Machine.store64(c, 0, n + 1)
    zr_fix(n)
  end

  # The class that the current box sees in place of `klass`: its shadow,
  # or the class itself.
  #: (value) -> value
  def zr_box_view(klass)
    if zr_special_p(klass)
      return klass
    end
    a = ClassExt[RClass[klass].ext].boxed
    if a == QNIL
      return klass
    end
    b = zr_box_reach()
    if b == QNIL
      return klass
    end
    i = zr_fix2long(zr_ivar_get(b, Machine.id(:slot)))
    if i >= RArray[a].len
      return klass
    end
    v = zr_ary_at(a, i)
    v == QNIL ? klass : v
  end

  # A method that the current box put on its own Object (a toplevel def
  # in the box) for a receiver whose own class the box does not shadow,
  # or 0. In ruby such a method is an entry of Object's table that only
  # the box sees, so it reaches every object of the box; here it is on
  # the box's Object shadow, which only an Object of the box has.
  #: (value, word) -> ptr
  def zr_box_object_method(recv, mid)
    object = zr_global(G_OBJECT)
    if ClassExt[RClass[object].ext].boxed == QNIL
      return 0
    end
    view = zr_box_view(object)
    if view == object || !zr_class_inherits(zr_class_of(recv), object)
      return 0
    end
    zr_find_method(view, mid)
  end

  # Sets `shadow` as the view of `klass` for the box slot.
  #: (value, value, value) -> value
  def zr_box_bind(klass, slot, shadow)
    ext = RClass[klass].ext
    a = ClassExt[ext].boxed
    if a == QNIL
      a = zr_ary_new(4)
      ClassExt[ext].boxed = a
      zr_write_barrier(klass, a)
    end
    i = zr_fix2long(slot)
    while RArray[a].len <= i
      zr_ary_push(a, Machine.value(QNIL))
    end
    zr_ary_store(a, i, shadow)
    ClassExt[RClass[shadow].ext].shadow = klass
    RBasic[klass].flags = RBasic[klass].flags & FL_RANKED_CLEAR
    RBasic[shadow].flags = RBasic[shadow].flags & FL_RANKED_CLEAR
    zr_write_barrier(shadow, klass)
    zr_methods_changed()
    Machine.value(QNIL)
  end

  # The shared class that a box shadow is in place of, or nil.
  #: (value) -> value
  def zr_box_origin(klass)
    if !zr_module_p(klass)
      return Machine.value(QNIL)
    end
    ClassExt[RClass[klass].ext].shadow
  end

  # Whether `klass` existed when the program started. A box can shadow
  # only such a class. A class that the program or a box made is not
  # shared.
  #: (value) -> value
  def zr_box_shared_p(klass)
    if !zr_module_p(klass)
      return Machine.value(QFALSE)
    end
    zr_bool(ClassExt[RClass[klass].ext].serial <= Machine.load64(Machine.static(:master_serial, 8), 0))
  end

  # Records the runtime state when the program starts: the constants of
  # Object, the classes that exist, and the globals that are set. A box
  # reads this state, never what the program adds to it.
  #: () -> value
  def zr_box_snapshot
    Machine.store64(Machine.static(:master_consts, 8), 0, ClassExt[RClass[zr_global(G_OBJECT)].ext].clen)
    Machine.store64(Machine.static(:master_serial, 8), 0, Machine.load64(Machine.static(:class_serial, 8), 0))
    h = zr_hash_new()
    t = zr_gvars()
    n = IvTab[t].len
    i = 0
    while i < n
      e = IvTab[t].rows + (i * IvEntry.size)
      zr_hash_store(h, zr_fix(IvEntry[e].id), IvEntry[e].value)
      i += 1
    end
    zr_set_global(G_MASTER_GVARS, h)
    Machine.value(QNIL)
  end

  # The number of Object's constant entries.
  #: () -> value
  def zr_box_object_consts_m
    zr_fix(ClassExt[RClass[zr_global(G_OBJECT)].ext].clen)
  end

  # Object's constant entries from entry `from` on, as [name, value]
  # pairs: the constants that a require made after that point. An
  # autoload's entry, which has no value yet, is left out.
  #: (value) -> value
  def zr_box_object_consts_from_m(from)
    out = zr_ary_new(4)
    ext = RClass[zr_global(G_OBJECT)].ext
    i = zr_fix2long(from)
    while i < ClassExt[ext].clen
      e = ClassExt[ext].ctab + (i * CEntry.size)
      if CEntry[e].value != QUNDEF
        pair = zr_ary_new(2)
        zr_ary_push(pair, zr_sym(CEntry[e].id))
        zr_ary_push(pair, CEntry[e].value)
        zr_ary_push(out, pair)
      end
      i += 1
    end
    out
  end

  # The globals of the runtime at the start. A new box copies them.
  #: () -> value
  def zr_box_master_gvars
    zr_global(G_MASTER_GVARS)
  end

  # Whether Object's constant entry `i` is one that the program wrote. A
  # box does not read such an entry.
  #: (value, word) -> bool
  def zr_box_const_hidden(klass, i)
    klass == zr_global(G_OBJECT) && i >= Machine.load64(Machine.static(:master_consts, 8), 0) && zr_box_current() != QNIL
  end

  # The box's table of globals.
  #: (value) -> value
  def zr_box_gvars(b)
    zr_ivar_get(b, Machine.id(:globals))
  end

  # When a box reads a shared class, it gets its shadow of that class.
  # This makes the shadow if the box has none. Other values do not change.
  #: (value) -> value
  def zr_box_seen(v)
    if zr_box_shared_p(v) != QTRUE
      return v
    end
    b = zr_box_current()
    if b == QNIL
      return v
    end
    s = zr_box_view(v)
    if s != v
      return s
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(v))
    zr_send(b, Machine.id(:__shadow__), 1, slot)
  end

  # A shadow returns the name of the shared class that it is in place of.
  #: (value, value) -> value
  def zr_box_name(klass, name)
    RClass[klass].name = name
    Machine.value(QNIL)
  end

  # The globals table key for a name symbol, after alias resolution.
  #: (value) -> value
  def zr_box_gvar_key(name)
    zr_fix(zr_gvar_resolve(zr_sym2id(name)))
  end
end
