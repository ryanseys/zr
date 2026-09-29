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
Machine.struct :RCref, basic: RBasic, klass: Value, next: Value, vis: Word, modfn: Word, eval: Word, entry: Ptr, lazy: Value
T_CREF = 25
# The `RCref.eval` value for a block that runs under an object with no
# singleton class, as in `1.instance_eval`. A `def` there has no class to
# define the method on.
EVAL_NO_DEF = 2
VIS_PUBLIC = 0
VIS_PRIVATE = 1
VIS_PROTECTED = 2
G_TOP_CREF = 24

sig [Value, Value] => Value
machine def zr_cref_push(klass, outer)
  c = zr_alloc(T_CREF, Machine.value(QNIL), RCref.size)
  RCref.set_klass(c, klass)
  RCref.set_next(c, outer)
  RCref.set_vis(c, VIS_PUBLIC)
  RCref.set_modfn(c, 0)
  RCref.set_eval(c, 0)
  RCref.set_entry(c, 0)
  RCref.set_lazy(c, Machine.value(QNIL))
  c
end

# Returns the class of a cref. If the cref is for the singleton class of
# an object and no code needed that class yet, it makes the class first.
sig [Value] => Value
machine def zr_cref_klass(cref)
  obj = RCref.lazy(cref)
  if obj != QNIL
    RCref.set_klass(cref, zr_singleton_class(obj))
    RCref.set_lazy(cref, Machine.value(QNIL))
  end
  RCref.klass(cref)
end

sig [Value, Value] => Value
machine def zr_cref_push_eval(klass, outer)
  c = zr_cref_push(klass, outer)
  RCref.set_eval(c, 1)
  c
end

# Whether two Values are the same object, without a method call on
# either. A cref has no class, so `equal?` on a cref cannot dispatch. The
# tree-walking interpreter keeps crefs and must tell them apart.
sig [Value, Value] => Value
machine def zr_same_p(a, b)
  zr_bool(a == b)
end

# A bare `private`, `public`, `protected` or `module_function` in a class
# body sets the visibility of that body, which is in its cref. Compiled
# code writes it where the body runs. The tree-walking interpreter has the
# cref but no frame of the body to write it in, so it writes it here.
# 0 is public, 1 is private, 2 is protected.
sig [Value, Value] => Value
machine def zr_cref_set_vis(cref, vis)
  RCref.set_vis(cref, zr_fix2long(vis))
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_cref_set_modfn(cref)
  RCref.set_modfn(cref, 1)
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_cref_lexical(cref)
  while RCref.eval(cref) != 0
    cref = RCref.next(cref)
  end
  cref
end

sig [Value] => Value
machine def zr_cref_lexical_class(cref)
  zr_cref_klass(zr_cref_lexical(cref))
end

# A constant table of this length or more has a hash index of its ids.
# The first lookup that needs the index builds it. Object's table has
# hundreds of entries, and every bare constant read ends there. A lookup
# scans a shorter table.
CONST_INDEX_MIN = 16

# Deletes the index. The next lookup that needs it builds it again.
sig [Ptr] => Void
machine def zr_const_index_drop(ext)
  if ClassExt.cidx(ext) != 0
    zr_xfree(ClassExt.cidx(ext))
    ClassExt.set_cidx(ext, 0)
  end
end

# Adds entry number `row` to the index. A bin contains the entry number
# plus one, or zero when empty. Entries go in in order, so when two
# entries have the same id, the lookup finds the earlier one first, as a
# scan does.
sig [Ptr, Word] => Void
machine def zr_const_index_put(ext, row)
  mask = ClassExt.cbins(ext) - 1
  h = (CEntry.id(ClassExt.ctab(ext) + (row * CEntry.size)) * 2654435761) & mask
  while Machine.load64(ClassExt.cidx(ext) + (h * 8), 0) != 0
    h = (h + 1) & mask
  end
  Machine.store64(ClassExt.cidx(ext) + (h * 8), 0, row + 1)
end

# Builds a new index of all entries, with at least four bins for each entry.
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

# Adds a new last entry to the index while the bins stay less than half
# full. Otherwise it deletes the index, and the next lookup builds a
# larger one.
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

# Returns the entry number of `id` in the table, or -1.
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

# Returns the constant entry for `id` on `klass` alone, or 0. The program
# cannot read an entry that the runtime hides.
sig [Value, Word] => Ptr
machine def zr_const_row(klass, id)
  e = zr_const_row_kept(klass, id)
  if e != 0 && CEntry.concealed(e) != 0 && !zr_const_sees_concealed()
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
# frame that called the core library.
sig [] => Bool
machine def zr_const_sees_concealed
  if zr_loading_hidden()
    return true
  end
  rec = Task.top(zr_task())
  reflective = Machine.load64(Machine.static(:const_reflective, 8), 0) > 0
  if !reflective && rec != 0 && (FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN || FrameMeta.kind(Frame.meta(rec)) == KIND_HIDDEN)
    return true
  end
  rec = zr_asking_frame()
  rec == 0 || FrameMeta.hidden(Frame.meta(rec)) != 0
end

# Whether a reflective read, such as Module#constants, sees a hidden
# constant entry.
sig [] => Bool
machine def zr_const_sees_reflectively
  depth = Machine.static(:const_reflective, 8)
  Machine.store64(depth, 0, Machine.load64(depth, 0) + 1)
  sees = zr_const_sees_concealed()
  Machine.store64(depth, 0, Machine.load64(depth, 0) - 1)
  sees
end

# Makes Object's constant `id` visible. A hidden file defined or reopened
# it, and now the program required that file itself.
sig [Word] => Void
machine def zr_const_reveal(id)
  e = zr_const_row_kept(zr_global(G_OBJECT), id)
  if e != 0 && CEntry.concealed(e) != 0
    CEntry.set_concealed(e, 0)
    zr_consts_changed()
  end
end

# Returns the constant entry that a `class` or `module` body opens. A
# hidden entry becomes visible, so a program that reopens a module of the
# runtime adds to the same module that the runtime uses. When a hidden
# file reopens it, the runtime records that file as one that defined it.
sig [Value, Word] => Ptr
machine def zr_const_row_opened(scope, id)
  e = zr_const_row_kept(scope, id)
  if e != 0 && CEntry.concealed(e) != 0
    if zr_hidden_now()
      zr_hidden_defined(id)
    else
      CEntry.set_concealed(e, 0)
      zr_consts_changed()
    end
  end
  e
end

# Returns the constant entry for `id` on `klass` alone, hidden or not, or 0.
sig [Value, Word] => Ptr
machine def zr_const_row_kept(klass, id)
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

# Stores a constant under `klass`, then calls the `const_added` hook. An
# anonymous class or module gets the name of the constant. Returns `v`,
# or undef when the store or the hook raises.
sig [Value, Word, Value] => Value
machine def zr_const_set(klass, id, v)
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
sig [Value, Word] => Value
machine def zr_const_announce(klass, id)
  if zr_frame_with_file(Task.top(zr_task())) != 0 && zr_find_method(zr_class_of(klass), Machine.id(:const_added)) != 0
    return zr_hook(klass, Machine.id(:const_added), zr_sym(id))
  end
  Machine.value(QNIL)
end

# Returns the constant entry of `klass` that contains `v` under `id`. It
# makes a new entry or uses the old one, and records the source position.
# Returns 0 when the store raises.
sig [Value, Word, Value] => Ptr
machine def zr_const_write(klass, id, v)
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
  if e != 0 && CEntry.concealed(e) != 0 && !zr_const_sees_concealed()
    # When the program sets a constant with a name that the runtime hides,
    # the program's constant takes the entry as a new one.
    CEntry.set_concealed(e, 0)
    CEntry.set_value(e, Machine.value(QUNDEF))
  end
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
        zr_xfree(ClassExt.ctab(ext))
      end
      ClassExt.set_ctab(ext, tab)
      ClassExt.set_ccap(ext, cap)
    end
    e = ClassExt.ctab(ext) + (n * CEntry.size)
    CEntry.set_id(e, id)
    CEntry.set_private(e, 0)
    CEntry.set_deprecated(e, 0)
    CEntry.set_owner(e, klass)
    CEntry.set_concealed(e, 0)
    if klass == zr_global(G_OBJECT) && zr_hidden_now()
      CEntry.set_concealed(e, 1)
      zr_hidden_defined(id)
    end
    ClassExt.set_clen(ext, n + 1)
    zr_const_index_add(ext, n)
  elsif CEntry.value(e) != QUNDEF
    zr_warn_reassigned_constant(klass, id, e)
  elsif v != QUNDEF
    # A value set on a name that still waits for its autoload file stays,
    # and the autoload stops waiting for the file.
    i = zr_autoload_row(klass, id)
    if i >= 0
      zr_ary_splice(zr_global(G_AUTOLOADS), zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
    end
  end
  CEntry.set_value(e, v)
  zr_write_barrier(klass, v)
  zr_consts_changed()
  # An anonymous class gets its name here. The name is permanent under a
  # scope with a permanent name (and then the classes it contains get
  # permanent names too). Otherwise the name is temporary.
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
    CEntry.set_line(e, zr_frame_line(top))
  end
  e
end

# Warns `already initialized constant M::X`, and gives the location of
# the first definition when the file is known. It warns nothing while the
# runtime boots.
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
  zr_buf_free(b)
end

# Appends `\nfile:line: previous definition of Name was here` to a
# message about a constant. A constant that the runtime set has no file
# and no line, and CRuby prints them empty.
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

# Returns the constant entry for `id` on `klass` or an ancestor, or 0.
# `skip_object` leaves out Object's own constants, as `A::X` does.
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

# The same lookup as a constant read. It skips a name that an autoload
# declared but that no file will define, and continues to the next
# ancestor. rb_const_search_from does this with its `am` guard: it runs
# the autoload once, finds the entry still undefined, and continues to
# the next ancestor. `rb_const_defined_0` does not: it stops at that
# entry and returns false. Thus a read and `const_defined?` differ here.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_read_in(klass, id, skip_object)
  while klass != QNIL
    unless skip_object && klass == zr_global(G_OBJECT)
      e = zr_const_row(klass, id)
      if e != 0 && !zr_const_declared_only(e)
        return e
      end
    end
    klass = RClass.superclass(klass)
  end
  0
end

# Whether `home` answers const_missing with a method that the program
# defined. Only such a method gets its own frame. The const_missing of
# Module raises where the lookup fails, as ruby's does.
sig [Value] => Bool
machine def zr_own_const_missing_p(home)
  entry = zr_find_method(zr_class_of(home), Machine.id(:const_missing))
  entry != 0 && entry != zr_find_method_at(zr_global(G_MODULE), Machine.id(:const_missing))
end

sig [Value, Word] => Value
machine def zr_send_const_missing(home, id)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(zr_sym(id)))
  zr_send(home, Machine.id(:const_missing), 1, slot)
end

# A private constant read as `scope::Name`: the scope's own const_missing
# answers, else the NameError names the class that holds the constant,
# as rb_const_get_0 and rb_mod_const_missing do.
sig [Value, Ptr, Word] => Value
machine def zr_private_constant_read(scope, e, id)
  return zr_send_const_missing(scope, id) if zr_own_const_missing_p(scope)
  zr_private_constant(CEntry.owner(e), id)
end

sig [Value, Word] => Value
machine def zr_uninitialized_constant(scope, id)
  home = scope == QNIL ? zr_global(G_OBJECT) : scope
  return zr_send_const_missing(home, id) if zr_own_const_missing_p(home)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("uninitialized constant "), 23)
  if scope != QNIL && scope != zr_global(G_OBJECT) && zr_class_of(scope) != zr_global(G_BOX)
    zr_buf_class(b, scope)
    zr_buf_push(b, Machine.bytes("::"), 2)
  end
  zr_buf_sym(b, id)
  e = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:name), zr_sym(id))
  zr_exc_detail(e, Machine.id(:receiver), scope == QNIL ? zr_global(G_OBJECT) : scope)
  zr_raise(e)
end

# Reads a bare constant under `cref`, or raises `uninitialized constant`.
sig [Value, Word] => Value
machine def zr_const_get(cref, id)
  cref = zr_cref_lexical(cref)
  gone = Machine.slot(16)
  while true
    e = zr_const_row_under(cref, id)
    if e == 0
      return zr_uninitialized_constant(zr_cref_klass(cref), id)
    end
    r = zr_const_deprecated(e, id)
    return r if r == QUNDEF
    v = zr_const_searched(e, gone)
    if Machine.load64(gone, 0) == 0
      return v
    end
  end
  Machine.value(QNIL)
end

# Returns the constant entry for a bare constant under `cref`, or 0. The
# search order is: the lexical scopes (the cref of an eval is not one),
# then the ancestors of the innermost scope, then the box's own toplevel
# and its own Object, then Object when that scope is a module.
sig [Value, Word] => Ptr
machine def zr_const_row_under(cref, id)
  cref = zr_cref_lexical(cref)
  c = cref
  while RCref.next(c) != QNIL
    if RCref.eval(c) == 0
      e = zr_const_row(zr_cref_klass(c), id)
      if e != 0 && !zr_const_declared_only(e)
        return e
      end
    end
    c = RCref.next(c)
  end
  e = zr_const_row_read_in(zr_cref_klass(cref), id, false)
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
  if e == 0 && zr_type(zr_cref_klass(cref)) == T_MODULE
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  e
end

# Reads a bare constant under `cref` for `||=`. Returns the value, or
# undef without a raise.
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

# Whether entry `e` is a name that an autoload declared and that no file
# defined. An autoload that still waits for its file also contains
# QUNDEF, and that one counts as defined. Thus the autoload table
# decides: if an autoload record refers to this entry and still waits,
# a file is still to come.
sig [Ptr] => Bool
machine def zr_const_declared_only(e)
  if CEntry.value(e) != QUNDEF
    return false
  end
  rows = zr_global(G_AUTOLOADS)
  if zr_special_p(rows)
    return true
  end
  i = 0
  while i < RArray.len(rows)
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
  zr_bool(e != 0 && CEntry.private(e) == 0 && !zr_const_declared_only(e))
end

# Raises `private constant Foo::BAR referenced`.
sig [Value, Word] => Value
machine def zr_private_constant(scope, id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("private constant "), 17)
  zr_buf_str(b, zr_class_to_s(scope, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
  zr_buf_push(b, Machine.bytes("::"), 2)
  zr_buf_sym(b, id)
  zr_buf_push(b, Machine.bytes(" referenced"), 11)
  exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
  zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
  zr_exc_detail(exc, Machine.id(:receiver), scope)
  zr_raise(exc)
end

# Sends the warning for a deprecated constant to `Warning`, so that a
# program can catch it or make it silent.
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
# `deprecate_constant(*names)` set a flag on the module's own entries.
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
      zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:receiver), recv)
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
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  zr_mod_constant_visibility(recv, argc, argv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_constant(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  zr_mod_constant_visibility(recv, argc, argv, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_deprecate_constant(recv, argc, argv, cref, blk)
  zr_mod_constant_visibility(recv, argc, argv, 0 - 1)
end

# Raises TypeError unless `scope` is a class or a module, as the scope of
# a constant path must be (`12::Name`, `class nil::Name`). Returns QUNDEF
# after the raise, else nil.
sig [Value] => Value
machine def zr_namespace_check(scope)
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
sig [Value, Word] => Value
machine def zr_const_get_at(scope, id)
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
    if CEntry.private(e) != 0
      return zr_private_constant_read(scope, e, id)
    end
    r = zr_const_deprecated(e, id)
    return r if r == QUNDEF
    v = zr_const_searched(e, gone)
    if Machine.load64(gone, 0) == 0
      return v
    end
  end
  Machine.value(QNIL)
end

# Returns the name that a class gets under `scope`: `Outer::Name`, but
# only `Name` when the scope is a toplevel (Object, or a box), and
# `#<Module:0x...>::Name` under an anonymous scope.
sig [Value, Word] => Value
machine def zr_class_name_under(scope, id)
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
  index = zr_enc_append(index, ascii, Buf.len(b), tail_ascii ? ENC_USASCII : zr_symbol_encoding_index(id), tail_ascii)
  zr_buf_sym(b, id)
  zr_class_name_str(zr_str_set_index(zr_buf_take(b), index))
end

# Returns the name of a class as rb_class_path keeps it. The name is
# frozen, so `Module#name` returns the class's own String.
sig [Value] => Value
machine def zr_class_name_str(s)
  RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE)
  s
end

# Whether a name made under `scope` is permanent. It is permanent under a
# toplevel, and under a scope that has a permanent name.
sig [Value] => Bool
machine def zr_class_named_for_good(scope)
  zr_toplevel_scope_p(scope) || (RClass.name(scope) != QNIL && (RBasic.flags(scope) & FL_TEMP_NAME) == 0)
end

# `mod` just got a permanent name. Each class or module that it contains
# and that has a temporary name gets its path under `mod`, recursively,
# as CRuby's set_namespace_path does.
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

# `class Name < sup` under `scope`. Returns the class of the constant when
# it exists (and its superclass agrees), else a new class. `sup` is undef
# when the program gave no superclass. `scoped` is 1 for a path with a
# scope (`class A::Name`, `class ::Name`), which cannot reopen a private
# constant.
sig [Value, Word, Value, Word] => Value
machine def zr_class_define(scope, id, sup, scoped)
  checked = zr_namespace_check(scope)
  return checked if checked == QUNDEF
  e = zr_const_row_opened(scope, id)
  if e == 0 && (scope == zr_global(G_OBJECT) || zr_box_current() != QNIL)
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e != 0 && CEntry.value(e) == QUNDEF && zr_autoload_pending(scope, id) < 0
    e = 0
  end
  k = Machine.value(QUNDEF)
  # vm_const_get_under: a scoped path reads the constant as a public one.
  if e != 0 && scoped != 0 && CEntry.private(e) != 0
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

sig [Value, Word, Word] => Value
machine def zr_module_define(scope, id, scoped)
  checked = zr_namespace_check(scope)
  return checked if checked == QUNDEF
  e = zr_const_row_opened(scope, id)
  if e == 0 && (scope == zr_global(G_OBJECT) || zr_box_current() != QNIL)
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  if e != 0 && CEntry.value(e) == QUNDEF && zr_autoload_pending(scope, id) < 0
    e = 0
  end
  m = Machine.value(QUNDEF)
  # vm_const_get_under: a scoped path reads the constant as a public one.
  if e != 0 && scoped != 0 && CEntry.private(e) != 0
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
sig [Value, Value] => Value
machine def zr_module_define_m(scope, name)
  zr_module_define(scope, zr_sym2id(name), 0)
end

# Writes the id of a constant name, given as a Symbol or String, to
# `out`. Otherwise raises `wrong constant name x`. A valid name is an
# upper-case letter, then letters, digits, underscores or non-ASCII bytes.
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
    zr_exc_detail(exc, Machine.id(:name), name)
    zr_exc_detail(exc, Machine.id(:receiver), recv)
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

# Returns the constant entry for one segment of a `const_get` path. The
# first segment uses the `const_get` lookup. A later segment leaves out
# Object's constants.
sig [Value, Word, Value, Value] => Ptr
machine def zr_const_row_segment(recv, id, inherit, later)
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

# Returns `[file, line]` of the entry, `[]` for an entry that the runtime
# made, or nil when there is no entry.
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
  id = Machine.load64(slot, 0)
  # `rb_const_defined_0` stops at an entry that an autoload declared and
  # that no file will define. It returns false there and does not continue,
  # so the name hides a name of its own farther out.
  e = zr_const_row_segment_defined(recv, id, inherit, later)
  zr_bool(e != 0 && !zr_const_declared_only(e))
end

# The `const_defined?` lookup, which stops at the first entry that it
# finds, declared or not.
sig [Value, Word, Value, Value] => Ptr
machine def zr_const_row_segment_defined(recv, id, inherit, later)
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
sig [Value, Word] => Ptr
machine def zr_const_row_defined_for(mod, id)
  e = zr_const_row_in(mod, id, false)
  if e == 0 && zr_type(mod) == T_MODULE
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  end
  e
end

# `remove_const(name)`: removes the module's own entry and returns its value.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_remove_const(recv, argc, argv, cref, blk)
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
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
    zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
    zr_exc_detail(exc, Machine.id(:receiver), recv)
    return zr_raise(exc)
  end
  v = CEntry.value(e)
  zr_const_remove(recv, id)
  # A name that still waits for its file also forgets the file, and
  # returns nil, as CRuby's rb_const_remove does.
  if v == QUNDEF
    i = zr_autoload_row(recv, id)
    if i >= 0
      zr_ary_splice(zr_global(G_AUTOLOADS), zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
    end
    return Machine.value(QNIL)
  end
  v
end

# Returns the constant entry that `const_get` and `const_defined?` find:
# the module's own, its ancestors' when `inherit` is true, and Object's
# for a module in all cases.
sig [Value, Word, Bool] => Ptr
machine def zr_const_row_for(mod, id, inherit)
  if inherit
    e = zr_const_row_read_in(mod, id, false)
    if e == 0 && zr_type(mod) == T_MODULE
      e = zr_const_row_read_in(zr_global(G_OBJECT), id, false)
    end
    return e
  end
  zr_const_row(mod, id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_const_set(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  slot = Machine.slot(8)
  r = zr_const_name_id(recv, Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  v = Machine.value(Machine.load64(argv, 8))
  if Task.ractor(zr_task()) != 0 && !zr_special_p(v)
    r = zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:const_write), 1, argv + 8)
    return r if r == QUNDEF
  end
  zr_const_set(recv, Machine.load64(slot, 0), v)
end

# Adds each public constant name of `klass` itself to `out`, once. A
# module that an extension defines under a name that is no constant name
# (IO::generic_readable) is left out, as rb_local_constants_i leaves out
# an id that is not rb_is_const_id.
sig [Value, Value] => Void
machine def zr_const_names_at(klass, out)
  ext = RClass.ext(klass)
  i = 0
  while i < ClassExt.clen(ext)
    e = ClassExt.ctab(ext) + (i * CEntry.size)
    id = CEntry.id(e)
    name = zr_sym(id)
    visible = CEntry.private(e) == 0 && (CEntry.concealed(e) == 0 || zr_const_sees_reflectively())
    if visible && zr_const_name_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id)) && zr_ary_index_of(out, name) < 0
      zr_ary_push(out, name)
    end
    i += 1
  end
end

# Adds the names of `mod`, then of its ancestors up to Object. The
# search stops at Object unless it started there, as rb_mod_const_of
# does: a class does not see the names of Object or BasicObject.
sig [Value, Value, Bool] => Void
machine def zr_const_names_of(mod, out, inherit)
  k = mod
  while k != QNIL && (k != zr_global(G_OBJECT) || mod == zr_global(G_OBJECT))
    zr_const_names_at(k, out)
    k = inherit ? RClass.superclass(k) : Machine.value(QNIL)
  end
end

# `Module.constants`. With no arguments, it lists the names of each
# lexical scope, then those of the ancestors of the innermost scope, as
# rb_mod_s_constants does. Otherwise it returns the same as
# `Module#constants`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_s_constants(recv, argc, argv, cref, blk)
  if argc != 0 || recv != zr_global(G_MODULE)
    return zr_mod_constants(recv, argc, argv, cref, blk)
  end
  out = zr_ary_new(8)
  c = zr_cref_lexical(Frame.cref(Frame.prev(Task.top(zr_task()))))
  inner = zr_cref_klass(c)
  while c != QNIL
    if RCref.eval(c) == 0
      zr_const_names_at(zr_cref_klass(c), out)
    end
    c = RCref.next(c)
  end
  zr_const_names_of(inner, out, true)
  out
end

# `constants`: the names of the receiver, and of its ancestors unless
# `inherit` is false.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_constants(recv, argc, argv, cref, blk)
  out = zr_ary_new(8)
  inherit = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_const_names_of(recv, out, inherit)
  out
end

# Removes the entry for `id` from the own table of `klass`.
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
      # The entries after it moved up by one.
      zr_const_index_drop(ext)
      zr_consts_changed()
      return
    end
    i += 1
  end
end

G_AUTOLOADS = 38

# Autoload: a constant entry whose value is undef until its file runs.
# Each record of G_AUTOLOADS has AUTOLOAD_ROW words: the module, the
# name, the feature as the program wrote it, the function of the unit as
# a fixnum, the require kind (zr_require's: 0, or 3 for eval support's
# own files), and the resolved path of the feature. A require of the same
# file records that path. A feature that the program computed has no
# unit. Its kind is AUTOLOAD_REQUIRE, and the first read of the constant
# calls `require` on main with it, as ruby's autoload does.
# `Kernel#autoload` and `Kernel.autoload` register on the class of the
# caller, as CRuby's rb_f_autoload does.
AUTOLOAD_ROW = 6
AUTOLOAD_REQUIRE = 4
# The kind of a record whose feature a require would not read, because
# the program contains it or a require already read it. The record stays, as ruby keeps its
# own, but it stops counting: `autoload?` returns nil and
# `const_defined?` returns false. The name is still declared, so the
# constant is undefined here and hides a constant of the same name
# farther out. A record gets this kind where it is registered, or where
# `zr_autoload_provided` finds the require that provided its feature.
AUTOLOAD_DECLARED = 5

sig [Value, Word, Value, Ptr, Value, Word, Value] => Value
machine def zr_autoload(mod, id, feature, fn, cref, kind, path)
  if mod == zr_global(G_MAIN) || mod == zr_global(G_KERNEL)
    mod = zr_cref_klass(zr_cref_lexical(cref))
  end
  # A name that already has a value stays, as `autoload_synchronized`
  # (variable.c:2913) returns false for it. A name with no value (undefined,
  # waiting for a file, or waiting for a file that another require
  # provided) is declared again, and calls the hook again.
  row = zr_const_row(mod, id)
  if row != 0 && CEntry.value(row) != QUNDEF
    return Machine.value(QNIL)
  end
  pending = zr_autoload_row(mod, id)
  rows = zr_global(G_AUTOLOADS)
  if zr_special_p(rows)
    rows = zr_ary_new(AUTOLOAD_ROW)
    zr_set_global(G_AUTOLOADS, rows)
  end
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
  if kind != AUTOLOAD_DECLARED && zr_ary_has_bytes(zr_gvar_get(Machine.id(:$LOADED_FEATURES)), RString.ptr(path), RString.len(path))
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
  zr_autoload_push(rows, mod, id, feature, fn, kind, path)
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
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_autoload_computed(mod, name, feature, cref, loaded, file)
  slot = Machine.slot(8)
  r = zr_name_id(name, slot)
  return r if r == QUNDEF
  id = Machine.load64(slot, 0)
  unless zr_const_name_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("autoload must be constant name: "), 32)
    zr_buf_sym(b, id)
    exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
    zr_exc_detail(exc, Machine.id(:name), zr_sym(id))
    return zr_raise(exc)
  end
  if RString.len(feature) == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty feature name"), 18)
  end
  zr_autoload(mod, id, feature, Machine.ptr(0), cref, loaded == QTRUE ? AUTOLOAD_DECLARED : AUTOLOAD_REQUIRE,
              zr_special_p(file) ? feature : file)
end

sig [Value, Value, Word, Value, Ptr, Word, Value] => Void
machine def zr_autoload_push(rows, mod, id, feature, fn, kind, path)
  zr_ary_push(rows, mod)
  zr_ary_push(rows, zr_sym(id))
  zr_ary_push(rows, feature)
  zr_ary_push(rows, zr_fix(Machine.word(fn)))
  zr_ary_push(rows, zr_fix(kind))
  zr_ary_push(rows, path)
end

# The first read of a constant whose feature the program computed. It
# calls `require` on main, which a program can redefine, as ruby does.
sig [Value] => Value
machine def zr_autoload_require(feature)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(feature))
  zr_send(zr_global(G_MAIN), Machine.id(:require), 1, slot)
end

# Whether the autoload record at `i` still waits for its file. A record
# whose feature another require provided does not wait:
# `check_autoload_required` (variable.c:3035) returns 0 for it, so
# `autoload?` returns nil and `const_defined?` returns false, and ruby
# keeps the record. Here that record has the kind AUTOLOAD_DECLARED, set
# where it was registered or by `zr_autoload_provided`.
sig [Value, Word] => Bool
machine def zr_autoload_waiting(rows, i)
  zr_fix2long(zr_ary_at(rows, i + 4)) != AUTOLOAD_DECLARED
end

# Returns the index of the autoload record for `mod` and `id` when a file
# is still to come, or -1. Most callers use this. The three callers that
# need the record in all cases (a second `autoload`, a value written on
# the name, and `remove_const`) use `zr_autoload_row`.
sig [Value, Word] => Word
machine def zr_autoload_pending(mod, id)
  i = zr_autoload_row(mod, id)
  if i < 0 || !zr_autoload_waiting(zr_global(G_AUTOLOADS), i)
    return 0 - 1
  end
  i
end

# A require read the file at `path`, which the program requested by the
# name `feature`. Every autoload record for either string stops waiting.
#
# ruby calls `rb_feature_provided` on the feature of the record each time
# it checks whether the record is pending. Here the check runs once, when
# the answer is known. The kernel cannot do the check later, because the
# resolution of a feature to a file is the work of `Kernel.feature_path`
# and uses $LOAD_PATH. It compares both strings because a record keeps the
# feature as written and the file that it resolved to at registration.
# If $LOAD_PATH grew between the two, only the feature can match.
sig [Value, Value] => Value
machine def zr_autoload_provided(feature, path)
  rows = zr_global(G_AUTOLOADS)
  if zr_special_p(rows)
    return Machine.value(QNIL)
  end
  i = 0
  while i < RArray.len(rows)
    if zr_autoload_names(zr_ary_at(rows, i + 2), feature) || zr_autoload_names(zr_ary_at(rows, i + 5), path)
      zr_ary_store(rows, i + 4, zr_fix(AUTOLOAD_DECLARED))
    end
    i += AUTOLOAD_ROW
  end
  Machine.value(QNIL)
end

# Whether the `kept` string of the record is `asked`. A record registered
# before its feature could be resolved has no path, and nothing matches it.
sig [Value, Value] => Bool
machine def zr_autoload_names(kept, asked)
  if zr_special_p(kept) || zr_special_p(asked) || zr_type(kept) != T_STRING || zr_type(asked) != T_STRING
    return false
  end
  zr_bytes_eq(RString.ptr(kept), RString.len(kept), RString.ptr(asked), RString.len(asked))
end

# Returns the index of the autoload record for `mod` and `id`, waiting or
# not, or -1.
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

# `autoload?(name)`: returns the feature still to load, or nil.
sig [Value, Word] => Value
machine def zr_autoload_feature(mod, id)
  i = zr_autoload_pending(mod, id)
  if i < 0
    return Machine.value(QNIL)
  end
  zr_ary_at(zr_global(G_AUTOLOADS), i + 2)
end

# Returns the value of a constant entry. An autoload's file runs first,
# and then the constant that it defined is the value. A file that defines
# nothing leaves the name uninitialized.
# A box that reads a shared class gets its shadow of that class.
sig [Ptr] => Value
machine def zr_const_value(e)
  zr_box_seen(zr_const_raw_value(e))
end

sig [Ptr] => Value
machine def zr_const_raw_value(e)
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
sig [Ptr, Ptr] => Value
machine def zr_const_searched(e, gone)
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
sig [Ptr, Ptr] => Value
machine def zr_const_loaded(e, gone)
  v = CEntry.value(e)
  if v != QUNDEF
    return v
  end
  rows = zr_global(G_AUTOLOADS)
  i = 0
  while i < RArray.len(rows)
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
      path = zr_ary_at(rows, i + 5)
      zr_ary_splice(rows, zr_fix(i), zr_fix(AUTOLOAD_ROW), zr_ary_new(0))
      r = kind == AUTOLOAD_REQUIRE ? zr_autoload_require(feature) : zr_require(path, fn, kind)
      # If the file did not load, the entry stays, so the next read of the name
      # does the same check again.
      if r == QUNDEF
        zr_autoload_push(rows, mod, id, feature, fn, kind, path)
        return r
      end
      e = zr_const_row(mod, id)
      if e == 0 || CEntry.value(e) == QUNDEF
        zr_const_remove(mod, id)
        Machine.store64(gone, 0, Machine.word(mod))
        Machine.store64(gone, 8, id)
        return Machine.value(QNIL)
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

# The tree-walking interpreter (lib/zr/eval/walk.rb) reads and writes
# constants through the kernel's own lookup, so a string that it evaluates
# finds what compiled code finds. It has no inline cache and no symbol id,
# so these functions take the name as a Symbol. They are in place of the
# cached forms that the compiler emits.
sig [Value, Value] => Value
machine def zr_const_get_m(cref, name)
  zr_const_get(cref, zr_sym2id(name))
end

sig [Value, Value] => Value
machine def zr_const_defined_m(cref, name)
  zr_const_defined(cref, zr_sym2id(name))
end

sig [Value, Value] => Value
machine def zr_const_get_at_m(scope, name)
  zr_const_get_at(scope, zr_sym2id(name))
end

sig [Value, Value] => Value
machine def zr_const_defined_at_m(scope, name)
  zr_const_defined_at(scope, zr_sym2id(name))
end

sig [Value, Value, Value] => Value
machine def zr_const_set_m(klass, name, v)
  zr_const_set(klass, zr_sym2id(name), v)
end
