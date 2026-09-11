# Constants and the lexical class chain. A cref cell names a class and
# the cref outside it; the toplevel's is Object alone. A constant read
# looks through the lexical chain (Object last, and only as an
# ancestor), then the innermost class's ancestors.
# `vis` is the visibility a def under the cref gets (VIS_*), and
# `modfn` whether `module_function` is on.
# A cref pushed by `class_eval`, `instance_eval` or `Class.new` (`eval`
# set) is where a `def` lands, but constants and class variables look
# through it to the lexical scope. The cref of a method `define_method`
# made names its entry, which `super` in the body resolves from.
Machine.struct :RCref, basic: RBasic, klass: Value, next: Value, vis: Word, modfn: Word, eval: Word, entry: Ptr
T_CREF = 25
VIS_PUBLIC = 0
VIS_PRIVATE = 1
VIS_PROTECTED = 2
G_TOP_CREF = 24

sig [Value, Value] => Value
machine def zr_cref_push(klass, outer)
  c = zr_alloc(T_CREF, Machine.value(QNIL))
  RCref.set_klass(c, klass)
  RCref.set_next(c, outer)
  RCref.set_vis(c, VIS_PUBLIC)
  RCref.set_modfn(c, 0)
  RCref.set_eval(c, 0)
  RCref.set_entry(c, 0)
  c
end

sig [Value, Value] => Value
machine def zr_cref_push_eval(klass, outer)
  c = zr_cref_push(klass, outer)
  RCref.set_eval(c, 1)
  c
end

# The innermost cref that names a lexical scope.
sig [Value] => Value
machine def zr_cref_lexical(cref)
  while RCref.eval(cref) != 0
    cref = RCref.next(cref)
  end
  cref
end

sig [Value] => Value
machine def zr_cref_lexical_class(cref)
  RCref.klass(zr_cref_lexical(cref))
end

# A table this long or longer is found through a hash index of its ids,
# built when a lookup first needs it: Object's holds hundreds of rows,
# and every bare constant a program reads ends there. A shorter table
# is scanned.
CONST_INDEX_MIN = 16

# The index forgotten; the next lookup that needs it builds it again.
sig [Ptr] => Void
machine def zr_const_index_drop(ext)
  if ClassExt.cidx(ext) != 0
    free(ClassExt.cidx(ext))
    ClassExt.set_cidx(ext, 0)
  end
end

# Row `row` into the index. A bin holds a row number plus one, zero
# when empty; rows go in in order, so of two rows with one id the
# earlier is found first, as a scan finds it.
sig [Ptr, Word] => Void
machine def zr_const_index_put(ext, row)
  mask = ClassExt.cbins(ext) - 1
  h = (CEntry.id(ClassExt.ctab(ext) + (row * CEntry.size)) * 2654435761) & mask
  while Machine.load64(ClassExt.cidx(ext) + (h * 8), 0) != 0
    h = (h + 1) & mask
  end
  Machine.store64(ClassExt.cidx(ext) + (h * 8), 0, row + 1)
end

# Every row into a fresh index with at least four bins a row.
sig [Ptr] => Void
machine def zr_const_index_build(ext)
  zr_const_index_drop(ext)
  n = ClassExt.clen(ext)
  bins = 64
  while bins < n * 4
    bins = bins * 2
  end
  ClassExt.set_cidx(ext, zr_xmalloc(bins * 8))
  memset(ClassExt.cidx(ext), Machine.i32(0), bins * 8)
  ClassExt.set_cbins(ext, bins)
  i = 0
  while i < n
    zr_const_index_put(ext, i)
    i += 1
  end
end

# A new last row: into the index while the bins stay under half full,
# else the index goes and the next lookup builds a bigger one.
sig [Ptr, Word] => Void
machine def zr_const_index_add(ext, row)
  if ClassExt.cidx(ext) == 0
    return
  end
  if (row + 1) * 2 > ClassExt.cbins(ext)
    zr_const_index_drop(ext)
    return
  end
  zr_const_index_put(ext, row)
end

# The row number of `id` in the table, or -1.
sig [Ptr, Word] => Word
machine def zr_const_index_find(ext, id)
  if ClassExt.cidx(ext) == 0
    zr_const_index_build(ext)
  end
  mask = ClassExt.cbins(ext) - 1
  h = (id * 2654435761) & mask
  slot = Machine.load64(ClassExt.cidx(ext) + (h * 8), 0)
  while slot != 0
    if CEntry.id(ClassExt.ctab(ext) + ((slot - 1) * CEntry.size)) == id
      return slot - 1
    end
    h = (h + 1) & mask
    slot = Machine.load64(ClassExt.cidx(ext) + (h * 8), 0)
  end
  0 - 1
end

# The constant row for `id` on `klass` alone, or 0.
sig [Value, Word] => Ptr
machine def zr_const_row(klass, id)
  ext = RClass.ext(klass)
  n = ClassExt.clen(ext)
  if n >= CONST_INDEX_MIN
    i = zr_const_index_find(ext, id)
    if i < 0
      return 0
    end
    return zr_box_const_hidden(klass, i) ? 0 : ClassExt.ctab(ext) + (i * CEntry.size)
  end
  i = 0
  while i < n
    e = ClassExt.ctab(ext) + (i * CEntry.size)
    if CEntry.id(e) == id
      return zr_box_const_hidden(klass, i) ? 0 : e
    end
    i += 1
  end
  0
end

# A constant stored under `klass`, then the `const_added` hook; an
# anonymous class or module takes the constant's name. Answers `v`,
# or undef when the hook raises.
sig [Value, Word, Value] => Value
machine def zr_const_set(klass, id, v)
  # `1::WHAT = 2` reaches here with a scope that holds no constants.
  if zr_special_p(klass) || (zr_type(klass) != T_CLASS && zr_type(klass) != T_MODULE)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    shown = zr_inspect(klass)
    return shown if shown == QUNDEF
    zr_buf_str(b, shown)
    zr_buf_push(b, Machine.bytes(" is not a class/module"), 22)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  e = zr_const_row(klass, id)
  if e == 0
    ext = RClass.ext(klass)
    n = ClassExt.clen(ext)
    if n == ClassExt.ccap(ext)
      cap = n * 2
      if cap < 8
        cap = 8
      end
      tab = zr_xmalloc(cap * CEntry.size)
      if ClassExt.ctab(ext) != 0
        zr_memcpy(tab, ClassExt.ctab(ext), n * CEntry.size)
        free(ClassExt.ctab(ext))
      end
      ClassExt.set_ctab(ext, tab)
      ClassExt.set_ccap(ext, cap)
    end
    e = ClassExt.ctab(ext) + (n * CEntry.size)
    CEntry.set_id(e, id)
    CEntry.set_private(e, 0)
    CEntry.set_deprecated(e, 0)
    CEntry.set_owner(e, klass)
    ClassExt.set_clen(ext, n + 1)
    zr_const_index_add(ext, n)
  elsif CEntry.value(e) != QUNDEF
    zr_warn_reassigned_constant(klass, id, e)
  end
  CEntry.set_value(e, v)
  zr_consts_changed()
  # An anonymous class takes its name here, for good under a scope that
  # has one for good (and then so does all it holds), else for now.
  if !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) && (RClass.name(v) == QNIL || (RBasic.flags(v) & FL_TEMP_NAME) != 0)
    RClass.set_name(v, zr_class_name_under(klass, id))
    if zr_class_named_for_good(klass)
      RBasic.set_flags(v, RBasic.flags(v) & (0 - (FL_TEMP_NAME + 1)))
      zr_name_nested(v)
    else
      RBasic.set_flags(v, RBasic.flags(v) | FL_TEMP_NAME)
    end
  end
  top = zr_frame_with_file(Task.top(zr_task()))
  if top == 0
    CEntry.set_file(e, 0)
    CEntry.set_file_len(e, 0)
    CEntry.set_line(e, 0)
  else
    CEntry.set_file(e, FrameMeta.file(Frame.meta(top)))
    CEntry.set_file_len(e, FrameMeta.file_len(Frame.meta(top)))
    CEntry.set_line(e, Frame.line(top))
  end
  if top != 0 && zr_find_method(zr_class_of(klass), Machine.id(:const_added)) != 0
    r = zr_hook(klass, Machine.id(:const_added), zr_sym(id))
    return r if r == QUNDEF
  end
  v
end

# `already initialized constant M::X`, and where the first definition
# was when a file is known; nothing while the runtime itself boots.
sig [Value, Word, Ptr] => Void
machine def zr_warn_reassigned_constant(klass, id, e)
  if Task.top(zr_task()) == 0 || zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL
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
  zr_warn_here(Buf.ptr(b), Buf.len(b))
  if CEntry.file_len(e) > 0
    Buf.set_len(b, 0)
    zr_buf_push(b, CEntry.file(e), CEntry.file_len(e))
    zr_buf_byte(b, 58)
    zr_buf_long(b, CEntry.line(e))
    zr_buf_push(b, Machine.bytes(": warning: previous definition of "), 34)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" was here\n"), 10)
    zr_write_err(Buf.ptr(b), Buf.len(b))
  end
  free(Buf.ptr(b))
end

# `\nfile:line: previous definition of Name was here` after a message
# about a constant; one the runtime set has no file and no line, and
# CRuby prints them empty.
sig [Ptr, Ptr, Word] => Void
machine def zr_buf_previous_definition(b, e, id)
  zr_buf_byte(b, 10)
  zr_buf_push(b, CEntry.file(e), CEntry.file_len(e))
  zr_buf_byte(b, 58)
  if CEntry.file_len(e) > 0
    zr_buf_long(b, CEntry.line(e))
  end
  zr_buf_push(b, Machine.bytes(": previous definition of "), 25)
  zr_buf_sym(b, id)
  zr_buf_push(b, Machine.bytes(" was here"), 9)
end

# The row for `id` on `klass` or an ancestor, or 0; `skip_object` leaves
# Object's own constants out, as `A::X` does.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_in(klass, id, skip_object)
  while klass != QNIL
    unless skip_object && klass == zr_global(G_OBJECT)
      e = zr_const_row(klass, id)
      if e != 0
        return e
      end
    end
    klass = RClass.superclass(klass)
  end
  0
end

sig [Value, Word] => Value
machine def zr_uninitialized_constant(scope, id)
  home = scope == QNIL ? zr_global(G_OBJECT) : scope
  entry = zr_find_method(zr_class_of(home), Machine.id(:const_missing))
  # Only a const_missing the program wrote gets a frame of its own; the
  # one Module carries raises right here, as ruby's does.
  if entry != 0 && entry != zr_find_method_at(zr_global(G_MODULE), Machine.id(:const_missing))
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_sym(id)))
    return zr_send(home, Machine.id(:const_missing), 1, slot)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("uninitialized constant "), 23)
  if scope != QNIL && scope != zr_global(G_OBJECT) && zr_class_of(scope) != zr_global(G_BOX)
    zr_buf_class(b, scope)
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  e = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:@name), zr_sym(id))
  zr_exc_detail(e, Machine.id(:@receiver), scope == QNIL ? zr_global(G_OBJECT) : scope)
  zr_raise(e)
end

# A bare constant under `cref`, or `uninitialized constant`.
sig [Value, Word] => Value
machine def zr_const_get(cref, id)
  cref = zr_cref_lexical(cref)
  e = zr_const_row_under(cref, id)
  if e == 0
    return zr_uninitialized_constant(RCref.klass(cref), id)
  end
  r = zr_const_deprecated(e, id)
  return r if r == QUNDEF
  zr_const_value(e)
end

# The row a bare constant under `cref` names, or 0: the lexical scopes
# (an eval's cref is not one), then the innermost scope's ancestors,
# then Object when that scope is a module.
sig [Value, Word] => Ptr
machine def zr_const_row_under(cref, id)
  cref = zr_cref_lexical(cref)
  c = cref
  while RCref.next(c) != QNIL
    if RCref.eval(c) == 0
      e = zr_const_row(RCref.klass(c), id)
      if e != 0
        return e
      end
    end
    c = RCref.next(c)
  end
  e = zr_const_row_in(RCref.klass(cref), id, false)
  if e == 0
    b = zr_box_current()
    if b != QNIL
      e = zr_const_row(b, id)
    end
  end
  if e == 0 && zr_type(RCref.klass(cref)) == T_MODULE
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  e
end

# A bare constant under `cref` for `||=`: the value, or undef with
# nothing raised.
sig [Value, Word] => Value
machine def zr_const_lookup(cref, id)
  e = zr_const_row_under(cref, id)
  if e == 0
    return Machine.value(QUNDEF)
  end
  zr_const_value(e)
end

sig [Value, Word] => Value
machine def zr_const_lookup_at(scope, id)
  if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
    return Machine.value(QUNDEF)
  end
  e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
  if e == 0 || CEntry.private(e) != 0
    return Machine.value(QUNDEF)
  end
  zr_const_value(e)
end

# `defined?` of a constant: true when a row exists, an autoload's
# included, with nothing loaded.
sig [Value, Word] => Value
machine def zr_const_defined(cref, id)
  zr_bool(zr_const_row_under(cref, id) != 0)
end

sig [Value, Word] => Value
machine def zr_const_defined_at(scope, id)
  if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
    return Machine.value(QFALSE)
  end
  e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
  zr_bool(e != 0 && CEntry.private(e) == 0)
end

# `private constant Foo::BAR referenced`.
sig [Value, Word] => Value
machine def zr_private_constant(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("private constant "), 17)
  if scope != zr_global(G_OBJECT)
    zr_buf_str(b, zr_class_to_s(scope, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  zr_buf_push(b, Machine.bytes(" referenced"), 11)
  exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
  zr_exc_detail(exc, Machine.id(:@receiver), scope)
  zr_raise(exc)
end

# The one warning a deprecated constant answers with, sent to
# `Warning` so a program can catch or silence it.
sig [Ptr, Word] => Value
machine def zr_const_deprecated(e, id)
  if CEntry.deprecated(e) == 0
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("constant "), 9)
  owner = CEntry.owner(e)
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
# `deprecate_constant(*names)`: a flag on the module's own rows.
sig [Value, Word, Ptr, Word] => Value
machine def zr_mod_constant_visibility(recv, argc, argv, private)
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
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
      zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:@receiver), recv)
      return zr_raise(exc)
    end
    if private < 0
      CEntry.set_deprecated(e, 1)
    else
      CEntry.set_private(e, private)
    end
    zr_consts_changed()
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_constant(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  zr_mod_constant_visibility(recv, argc, argv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_constant(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  zr_mod_constant_visibility(recv, argc, argv, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_deprecate_constant(recv, argc, argv, cref, blk)
  zr_mod_constant_visibility(recv, argc, argv, 0 - 1)
end

# `scope::Name`.
sig [Value, Word] => Value
machine def zr_const_get_at(scope, id)
  if zr_special_p(scope) || (zr_type(scope) != T_CLASS && zr_type(scope) != T_MODULE)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    s = zr_inspect(scope)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    zr_buf_push(b, Machine.bytes(" is not a class/module"), 22)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  e = zr_const_row_in(scope, id, scope != zr_global(G_OBJECT))
  if e == 0 && zr_class_of(scope) == zr_global(G_BOX)
    # `box::Name`: the box's own, else what the runtime itself holds.
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e == 0
    return zr_uninitialized_constant(scope, id)
  end
  if CEntry.private(e) != 0
    return zr_private_constant(scope, id)
  end
  r = zr_const_deprecated(e, id)
  return r if r == QUNDEF
  zr_const_value(e)
end

# The name a class gets under `scope`: `Outer::Name` unless the scope
# is a toplevel (Object, or a box), and `#<Module:0x...>::Name` under
# an anonymous one.
sig [Value, Word] => Value
machine def zr_class_name_under(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  unless zr_toplevel_scope_p(scope)
    zr_buf_str(b, zr_class_path(scope))
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  zr_buf_take(b)
end

# Whether a name made under `scope` is for good: a toplevel's is, and
# so is one under a scope whose own name is.
sig [Value] => Bool
machine def zr_class_named_for_good(scope)
  zr_toplevel_scope_p(scope) || (RClass.name(scope) != QNIL && (RBasic.flags(scope) & FL_TEMP_NAME) == 0)
end

# `mod` has just been named for good: each class or module it holds
# whose name is still temporary takes its path under `mod`, and so on
# down, as CRuby's set_namespace_path does.
sig [Value] => Void
machine def zr_name_nested(mod)
  ext = RClass.ext(mod)
  i = 0
  while i < ClassExt.clen(ext)
    v = CEntry.value(ClassExt.ctab(ext) + (i * CEntry.size))
    if v != QUNDEF && !zr_special_p(v) && (zr_type(v) == T_CLASS || zr_type(v) == T_MODULE) && (RBasic.flags(v) & FL_TEMP_NAME) != 0
      RBasic.set_flags(v, RBasic.flags(v) & (0 - (FL_TEMP_NAME + 1)))
      RClass.set_name(v, zr_class_name_under(mod, CEntry.id(ClassExt.ctab(ext) + (i * CEntry.size))))
      zr_name_nested(v)
    end
    i += 1
  end
end

# `class Name < sup` under `scope`: the class the constant names when it
# exists (and its superclass agrees), else a new one. `sup` is undef
# when the program wrote no superclass.
sig [Value, Word, Value] => Value
machine def zr_class_define(scope, id, sup)
  e = zr_const_row(scope, id)
  if e == 0 && (scope == zr_global(G_OBJECT) || zr_box_current() != QNIL)
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e != 0 && CEntry.value(e) == QUNDEF && zr_autoload_row(scope, id) < 0
    e = 0
  end
  if e != 0
    k = zr_const_value(e)
    return k if k == QUNDEF
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

sig [Value, Word] => Value
machine def zr_module_define(scope, id)
  e = zr_const_row(scope, id)
  if e == 0 && (scope == zr_global(G_OBJECT) || zr_box_current() != QNIL)
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e != 0 && CEntry.value(e) == QUNDEF && zr_autoload_row(scope, id) < 0
    e = 0
  end
  if e != 0
    m = zr_const_value(e)
    return m if m == QUNDEF
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

# A constant's name given as a Symbol or String, as its id in `out`;
# `wrong constant name x` otherwise: an upper-case letter, then letters,
# digits, underscores or bytes past ASCII.
sig [Value, Value, Ptr] => Value
machine def zr_const_name_id(recv, name, out)
  r = zr_name_id(name, out)
  return r if r == QUNDEF
  id = Machine.load64(out, 0)
  unless zr_const_name_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong constant name "), 20)
    zr_buf_sym(b, id)
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
    zr_exc_detail(exc, Machine.id(:@name), name)
    zr_exc_detail(exc, Machine.id(:@receiver), recv)
    return zr_raise(exc)
  end
  Machine.value(QNIL)
end

sig [Ptr, Word] => Bool
machine def zr_const_name_p(p, n)
  if n == 0
    return false
  end
  c = Machine.word(Machine.load8(p, 0))
  if c < 65 || c > 90
    return false
  end
  i = 1
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    alpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    unless alpha || (c >= 48 && c <= 57) || c == 95 || c >= 128
      return false
    end
    i += 1
  end
  true
end

# The row one segment of a `const_get` path names: the first segment
# as `const_get` finds it, a later one without Object's constants.
sig [Value, Word, Value, Value] => Ptr
machine def zr_const_row_segment(recv, id, inherit, later)
  if inherit == QFALSE || inherit == QNIL
    return zr_const_row(recv, id)
  end
  if later == QTRUE
    return zr_const_row_in(recv, id, recv != zr_global(G_OBJECT))
  end
  zr_const_row_for(recv, id, true)
end

sig [Value, Value, Value, Value] => Value
machine def zr_mod_const_get_m(recv, name, inherit, later)
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, name, slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  e = zr_const_row_segment(recv, id, inherit, later)
  if e == 0
    return zr_uninitialized_constant(recv, id)
  end
  zr_const_value(e)
end

# `[file, line]` of the row, `[]` for one the runtime made, nil for
# none.
sig [Value, Value, Value, Value] => Value
machine def zr_mod_const_source_location_m(recv, name, inherit, later)
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, name, slot)
  return r if r == QUNDEF
  e = zr_const_row_segment(recv, Machine.load64(slot, 0), inherit, later)
  if e == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(2)
  if CEntry.file_len(e) > 0
    zr_ary_push(out, zr_str_new(CEntry.file(e), CEntry.file_len(e)))
    zr_ary_push(out, zr_fix(CEntry.line(e)))
  end
  out
end

sig [Value, Value, Value, Value] => Value
machine def zr_mod_const_defined_m(recv, name, inherit, later)
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, name, slot)
  return r if r == QUNDEF
  zr_bool(zr_const_row_segment(recv, Machine.load64(slot, 0), inherit, later) != 0)
end

# `remove_const(name)`: the module's own row goes, and its value
# answers.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_remove_const(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
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
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
    zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
    zr_exc_detail(exc, Machine.id(:@receiver), recv)
    return zr_raise(exc)
  end
  v = CEntry.value(e)
  zr_const_remove(recv, id)
  # A name still waiting for its file forgets the file too, and answers
  # nil, as CRuby's rb_const_remove does.
  if v == QUNDEF
    i = zr_autoload_row(recv, id)
    if i >= 0
      zr_ary_splice(zr_global(G_AUTOLOADS), zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
    end
    return Machine.value(QNIL)
  end
  v
end

# The row `const_get` and `const_defined?` find: the module's own, its
# ancestors' when `inherit`, and Object's for a module either way.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_for(mod, id, inherit)
  if inherit
    e = zr_const_row_in(mod, id, false)
    if e == 0 && zr_type(mod) == T_MODULE
      e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    end
    return e
  end
  zr_const_row(mod, id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_const_set(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_const_set(recv, Machine.load64(slot, 0), Machine.value(Machine.load64(argv, 8)))
end

# The public constant names `klass` itself holds, each once into `out`.
sig [Value, Value] => Void
machine def zr_const_names_at(klass, out)
  ext = RClass.ext(klass)
  i = 0
  while i < ClassExt.clen(ext)
    e = ClassExt.ctab(ext) + (i * CEntry.size)
    name = zr_sym(CEntry.id(e))
    if CEntry.private(e) == 0 && zr_ary_index_of(out, name) < 0
      zr_ary_push(out, name)
    end
    i += 1
  end
end

# `mod`'s own names, then its ancestors' up to Object, which only
# Object itself includes.
sig [Value, Value, Bool] => Void
machine def zr_const_names_of(mod, out, inherit)
  k = mod
  while k != QNIL
    if k != zr_global(G_OBJECT) || mod == zr_global(G_OBJECT)
      zr_const_names_at(k, out)
    end
    k = inherit ? RClass.superclass(k) : Machine.value(QNIL)
  end
end

# `constants`: the receiver's names, or, for a bare `Module.constants`,
# the names each lexical scope holds and then the innermost scope's
# ancestors'.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_constants(recv, argc, argv, cref, blk)
  out = zr_ary_new(8)
  if argc == 0 && recv == zr_global(G_MODULE)
    c = zr_cref_lexical(Frame.cref(Frame.prev(Task.top(zr_task()))))
    inner = RCref.klass(c)
    while c != QNIL
      if RCref.eval(c) == 0
        zr_const_names_at(RCref.klass(c), out)
      end
      c = RCref.next(c)
    end
    zr_const_names_of(inner, out, true)
    return out
  end
  inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_const_names_of(recv, out, inherit)
  out
end

# `Module.nesting`: the lexical scopes open where the call was made,
# innermost first. The chain's last node is Object, which is not one.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_nesting(recv, argc, argv, cref, blk)
  out = zr_ary_new(4)
  c = zr_cref_lexical(Frame.cref(Frame.prev(Task.top(zr_task()))))
  while RCref.next(c) != QNIL
    if RCref.eval(c) == 0
      zr_ary_push(out, RCref.klass(c))
    end
    c = RCref.next(c)
  end
  out
end

# The row for `id` taken out of `klass`'s own table.
sig [Value, Word] => Void
machine def zr_const_remove(klass, id)
  ext = RClass.ext(klass)
  n = ClassExt.clen(ext)
  i = 0
  while i < n
    e = ClassExt.ctab(ext) + (i * CEntry.size)
    if CEntry.id(e) == id
      zr_memmove(e, e + CEntry.size, (n - i - 1) * CEntry.size)
      ClassExt.set_clen(ext, n - 1)
      # The rows after it moved up one.
      zr_const_index_drop(ext)
      zr_consts_changed()
      return
    end
    i += 1
  end
end

G_AUTOLOADS = 38

# Autoload: a constant row whose value is undef until its file runs.
# The rows of G_AUTOLOADS hold, AUTOLOAD_ROW words each, the module, the
# name, the feature, the unit's function as a fixnum, and the kind the
# file is required with (zr_require's: 0, or 3 for the eval road's own).
# `Kernel#autoload` and `Kernel.autoload` register on the caller's
# class, as CRuby's rb_f_autoload does.
AUTOLOAD_ROW = 5

sig [Value, Word, Value, Ptr, Value, Word] => Value
machine def zr_autoload(mod, id, feature, fn, cref, kind)
  if mod == zr_global(G_MAIN) || mod == zr_global(G_KERNEL)
    mod = RCref.klass(zr_cref_lexical(cref))
  end
  # A name that already holds a value stands; a name still waiting for
  # its file is declared again, and announces again.
  pending = zr_autoload_row(mod, id)
  if zr_const_row(mod, id) != 0 && pending < 0
    return Machine.value(QNIL)
  end
  rows = zr_global(G_AUTOLOADS)
  if zr_special_p(rows)
    rows = zr_ary_new(AUTOLOAD_ROW)
    zr_set_global(G_AUTOLOADS, rows)
  end
  if pending >= 0
    zr_ary_splice(rows, zr_fix(pending), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
  end
  zr_const_set(mod, id, Machine.value(QUNDEF))
  zr_autoload_push(rows, mod, id, feature, fn, kind)
  Machine.value(QNIL)
end

sig [Value, Value, Word, Value, Ptr, Word] => Void
machine def zr_autoload_push(rows, mod, id, feature, fn, kind)
  zr_ary_push(rows, mod)
  zr_ary_push(rows, zr_sym(id))
  zr_ary_push(rows, feature)
  zr_ary_push(rows, zr_fix(Machine.word(fn)))
  zr_ary_push(rows, zr_fix(kind))
end

# The autoload row index for `mod` and `id`, or -1.
sig [Value, Word] => Word
machine def zr_autoload_row(mod, id)
  rows = zr_global(G_AUTOLOADS)
  if zr_special_p(rows)
    return 0 - 1
  end
  i = 0
  while i < RArray.len(rows)
    if zr_ary_at(rows, i) == mod && zr_ary_at(rows, i + 1) == zr_sym(id)
      return i
    end
    i += AUTOLOAD_ROW
  end
  0 - 1
end

# `autoload?(name)`: the feature still to load, or nil.
sig [Value, Word] => Value
machine def zr_autoload_feature(mod, id)
  i = zr_autoload_row(mod, id)
  if i < 0
    return Machine.value(QNIL)
  end
  zr_ary_at(zr_global(G_AUTOLOADS), i + 2)
end

# The value of a constant row: an autoload's file runs first, and the
# constant it defined answers; a file that defines nothing leaves the
# name uninitialized.
# A shared class a box reads is the box's shadow of it.
sig [Ptr] => Value
machine def zr_const_value(e)
  zr_box_seen(zr_const_raw_value(e))
end

sig [Ptr] => Value
machine def zr_const_raw_value(e)
  v = CEntry.value(e)
  if v != QUNDEF
    return v
  end
  rows = zr_global(G_AUTOLOADS)
  i = 0
  while i < RArray.len(rows)
    mod = zr_ary_at(rows, i)
    id = zr_sym2id(zr_ary_at(rows, i + 1))
    if zr_const_row(mod, id) == e
      feature = zr_ary_at(rows, i + 2)
      fn = Machine.ptr(zr_fix2long(zr_ary_at(rows, i + 3)))
      kind = zr_fix2long(zr_ary_at(rows, i + 4))
      zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
      r = zr_require(feature, fn, kind)
      # A file that did not load leaves the row in place, so the next
      # read of the name asks the same question again.
      if r == QUNDEF
        zr_autoload_push(rows, mod, id, feature, fn, kind)
        return r
      end
      e = zr_const_row(mod, id)
      if e == 0 || CEntry.value(e) == QUNDEF
        zr_const_remove(mod, id)
        return zr_uninitialized_constant(mod, id)
      end
      return CEntry.value(e)
    end
    i += AUTOLOAD_ROW
  end
  zr_uninitialized_constant(Machine.value(QNIL), CEntry.id(e))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_autoload_p(recv, argc, argv, cref, blk)
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_autoload_feature(recv, Machine.load64(slot, 0))
end
