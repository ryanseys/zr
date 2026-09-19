# Ruby::Box: a box is a module that stands for its own view of the
# world. A class the box patches gets a SHADOW -- a class of its own
# whose superclass is the shared one -- and every lookup the box makes
# reads the shadow first. Toplevel constants and globals a box writes
# are its own, and what it reads back of main's is only what the
# runtime held when the program started.
G_MASTER_GVARS = 48
G_BOX = 49

# The Ruby::Box class, which the core library names here.
sig [Value] => Value
machine def zr_box_register(klass)
  zr_set_global(G_BOX, klass)
  Machine.value(QNIL)
end

# Whether `scope` is a toplevel: Object, or a box, whose toplevel
# constants are its own. A class set there is named by itself, as a
# class set on Object is.
sig [Value] => Bool
machine def zr_toplevel_scope_p(scope)
  if scope == zr_global(G_OBJECT)
    return true
  end
  box = zr_global(G_BOX)
  !zr_special_p(box) && zr_real_class(scope) == box
end

# The box the running code belongs to, which is the box its FUNCTION
# was written in: code the runtime itself carries is main's however a
# box reaches it.
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

# The box a call REACHES from: a builtin runs inside whoever called
# it, the way a C method does, so the walk goes past every one.
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

# The snippet's own toplevel names itself in a backtrace.
sig [Value] => Value
machine def zr_box_compiled(meta)
  FrameMeta.set_kind(Machine.ptr(zr_fix2long(meta)), KIND_COMPILED)
  Machine.value(QNIL)
end

# Every function of a box's own unit names the box, so its reach is
# the code the box holds and nothing else. A constant cell filled while
# that code was nobody's stands no longer.
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

# The next box's slot, which indexes the shadow list every class keeps.
sig [] => Value
machine def zr_box_slot
  c = Machine.static(:box_slots, 8)
  n = Machine.load64(c, 0)
  Machine.store64(c, 0, n + 1)
  zr_fix(n)
end

# What the current box sees in place of `klass`: the shadow it made, or
# the class itself.
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

# `shadow` becomes the box slot's view of `klass`.
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
  zr_write_barrier(shadow, klass)
  zr_methods_changed()
  Machine.value(QNIL)
end

# The shared class a box shadow stands for, or nil.
sig [Value] => Value
machine def zr_box_origin(klass)
  if !zr_module_p(klass)
    return Machine.value(QNIL)
  end
  ClassExt.shadow(RClass.ext(klass))
end

# Whether `klass` was there when the program started, which is what a
# box may shadow; a class the program or a box made is its own.
sig [Value] => Value
machine def zr_box_shared_p(klass)
  if !zr_module_p(klass)
    return Machine.value(QFALSE)
  end
  zr_bool(ClassExt.serial(RClass.ext(klass)) <= Machine.load64(Machine.static(:master_serial, 8), 0))
end

# What the runtime holds when the program starts: the constants Object
# carries, the classes that exist, and the globals that are set. A box
# reads these, never what the program adds to them.
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

# The globals the runtime held at the start, which a new box copies.
sig [] => Value
machine def zr_box_master_gvars
  zr_global(G_MASTER_GVARS)
end

# Whether Object's constant row `i` is one the program wrote, which a
# box does not read.
sig [Value, Word] => Bool
machine def zr_box_const_hidden(klass, i)
  klass == zr_global(G_OBJECT) && i >= Machine.load64(Machine.static(:master_consts, 8), 0) && zr_box_current() != QNIL
end

# The box's own table of globals.
sig [Value] => Value
machine def zr_box_gvars(b)
  zr_ivar_get(b, Machine.id(:globals))
end

# A shared class a box reads is the box's shadow of it, made now when
# it has none. Anything else is itself.
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

# A shadow answers the name of the class it stands over.
sig [Value, Value] => Value
machine def zr_box_name(klass, name)
  RClass.set_name(klass, name)
  Machine.value(QNIL)
end

# The globals table key a name symbol has, past any alias.
sig [Value] => Value
machine def zr_box_gvar_key(name)
  zr_fix(zr_gvar_resolve(zr_sym2id(name)))
end
