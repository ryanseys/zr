# Ruby::Box. A box is a module that represents its own view of the
# program state. When a box patches a class, the class gets a SHADOW: a
# separate class whose superclass is the shared class. Each lookup in
# the box reads the shadow first. The toplevel constants and globals
# that a box writes belong to the box. Of main's state, a box reads only
# what the runtime contained when the program started.
G_MASTER_GVARS = 48
G_BOX = 49

# The Ruby::Box class, which the core library sets here.
sig [Value] => Value
machine def zr_box_register(klass)
  zr_set_global(G_BOX, klass)
  Machine.value(QNIL)
end

# Whether `scope` is a toplevel: Object, or a box, which has its own
# toplevel constants. A class set there gets its plain name, as for a
# class set on Object.
sig [Value] => Bool
machine def zr_toplevel_scope_p(scope)
  if scope == zr_global(G_OBJECT)
    return true
  end
  box = zr_global(G_BOX)
  !zr_special_p(box) && zr_real_class(scope) == box
end

# The box of the running code, which is the box where its FUNCTION was
# written. Code that is part of the runtime belongs to main, even when a
# box calls it.
sig [] => Value
machine def zr_box_current
  t = Task.top(zr_task())
  if t == 0
    return Machine.value(QNIL)
  end
  m = Frame.meta(t)
  if m == 0
    return Machine.value(QNIL)
  end
  b = FrameMeta.box(m)
  Machine.word(b) == 0 ? Machine.value(QNIL) : b
end

# The box that a call COMES from. A builtin runs inside its caller, as a
# C method does, so the frame walk skips all builtins.
sig [] => Value
machine def zr_box_reach
  f = Task.top(zr_task())
  while f != 0
    m = Frame.meta(f)
    if m == 0
      return Machine.value(QNIL)
    end
    if FrameMeta.kind(m) != KIND_BUILTIN && FrameMeta.kind(m) != KIND_HIDDEN
      b = FrameMeta.box(m)
      return Machine.word(b) == 0 ? Machine.value(QNIL) : b
    end
    f = Frame.prev(f)
  end
  Machine.value(QNIL)
end

# The snippet's toplevel shows its own label in a backtrace.
sig [Value] => Value
machine def zr_box_compiled(meta)
  FrameMeta.set_kind(Machine.ptr(zr_fix2long(meta)), KIND_COMPILED)
  Machine.value(QNIL)
end

# Each function of a box's own unit refers to the box. Thus the box
# applies to its own code and to nothing else. A constant cache entry
# filled before the code had a box is not valid after this.
sig [Value, Value] => Value
machine def zr_box_stamp(metas, b)
  i = 0
  while i < RArray.len(metas)
    FrameMeta.set_box(Machine.ptr(zr_fix2long(zr_ary_at(metas, i))), b)
    i += 1
  end
  zr_consts_changed()
  Machine.value(QNIL)
end

# The slot of the next box. It is the index into the shadow list that
# each class keeps.
sig [] => Value
machine def zr_box_slot
  c = Machine.static(:box_slots, 8)
  n = Machine.load64(c, 0)
  Machine.store64(c, 0, n + 1)
  zr_fix(n)
end

# The class that the current box sees in place of `klass`: its shadow,
# or the class itself.
sig [Value] => Value
machine def zr_box_view(klass)
  if zr_special_p(klass)
    return klass
  end
  a = ClassExt.boxed(RClass.ext(klass))
  if a == QNIL
    return klass
  end
  b = zr_box_reach()
  if b == QNIL
    return klass
  end
  i = zr_fix2long(zr_ivar_get(b, Machine.id(:slot)))
  if i >= RArray.len(a)
    return klass
  end
  v = zr_ary_at(a, i)
  v == QNIL ? klass : v
end

# Sets `shadow` as the view of `klass` for the box slot.
sig [Value, Value, Value] => Value
machine def zr_box_bind(klass, slot, shadow)
  ext = RClass.ext(klass)
  a = ClassExt.boxed(ext)
  if a == QNIL
    a = zr_ary_new(4)
    ClassExt.set_boxed(ext, a)
    zr_write_barrier(klass, a)
  end
  i = zr_fix2long(slot)
  while RArray.len(a) <= i
    zr_ary_push(a, Machine.value(QNIL))
  end
  zr_ary_store(a, i, shadow)
  ClassExt.set_shadow(RClass.ext(shadow), klass)
  RBasic.set_flags(klass, RBasic.flags(klass) & FL_RANKED_CLEAR)
  RBasic.set_flags(shadow, RBasic.flags(shadow) & FL_RANKED_CLEAR)
  zr_write_barrier(shadow, klass)
  zr_methods_changed()
  Machine.value(QNIL)
end

# The shared class that a box shadow is in place of, or nil.
sig [Value] => Value
machine def zr_box_origin(klass)
  if !zr_module_p(klass)
    return Machine.value(QNIL)
  end
  ClassExt.shadow(RClass.ext(klass))
end

# Whether `klass` existed when the program started. A box can shadow
# only such a class. A class that the program or a box made is not
# shared.
sig [Value] => Value
machine def zr_box_shared_p(klass)
  if !zr_module_p(klass)
    return Machine.value(QFALSE)
  end
  zr_bool(ClassExt.serial(RClass.ext(klass)) <= Machine.load64(Machine.static(:master_serial, 8), 0))
end

# Records the runtime state when the program starts: the constants of
# Object, the classes that exist, and the globals that are set. A box
# reads this state, never what the program adds to it.
sig [] => Value
machine def zr_box_snapshot
  Machine.store64(Machine.static(:master_consts, 8), 0, ClassExt.clen(RClass.ext(zr_global(G_OBJECT))))
  Machine.store64(Machine.static(:master_serial, 8), 0, Machine.load64(Machine.static(:class_serial, 8), 0))
  h = zr_hash_new()
  t = zr_gvars()
  n = IvTab.len(t)
  i = 0
  while i < n
    e = IvTab.rows(t) + (i * IvEntry.size)
    zr_hash_store(h, zr_fix(IvEntry.id(e)), IvEntry.value(e))
    i += 1
  end
  zr_set_global(G_MASTER_GVARS, h)
  Machine.value(QNIL)
end

# The globals of the runtime at the start. A new box copies them.
sig [] => Value
machine def zr_box_master_gvars
  zr_global(G_MASTER_GVARS)
end

# Whether Object's constant entry `i` is one that the program wrote. A
# box does not read such an entry.
sig [Value, Word] => Bool
machine def zr_box_const_hidden(klass, i)
  klass == zr_global(G_OBJECT) && i >= Machine.load64(Machine.static(:master_consts, 8), 0) && zr_box_current() != QNIL
end

# The box's table of globals.
sig [Value] => Value
machine def zr_box_gvars(b)
  zr_ivar_get(b, Machine.id(:globals))
end

# When a box reads a shared class, it gets its shadow of that class.
# This makes the shadow if the box has none. Other values do not change.
sig [Value] => Value
machine def zr_box_seen(v)
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
sig [Value, Value] => Value
machine def zr_box_name(klass, name)
  RClass.set_name(klass, name)
  Machine.value(QNIL)
end

# The globals table key for a name symbol, after alias resolution.
sig [Value] => Value
machine def zr_box_gvar_key(name)
  zr_fix(zr_gvar_resolve(zr_sym2id(name)))
end
