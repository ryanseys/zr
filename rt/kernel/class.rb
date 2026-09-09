# Classes and modules: a name, a superclass, and an extension outside
# the arena holding the method table (id, code, arity, kind, meta,
# cref rows searched in order) and the constant table (id, value rows).
# An included module sits in the superclass chain as a proxy (T_ICLASS)
# that shares the module's extension and names it as `attached`.
# Method code takes `(recv, argc, argv, cref)` and answers a Value; the
# cref is the lexical class chain the method was defined under.
# `origin` is the proxy that holds a prepended class's own methods,
# placed below the prepended modules, or nil.
Machine.struct :RClass, basic: RBasic, name: Value, superclass: Value, ext: Ptr, attached: Value, origin: Value
Machine.struct :ClassExt, mtab: Ptr, mlen: Word, mcap: Word, ctab: Ptr, clen: Word, ccap: Word, iv: IvTab, cv: IvTab
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value, vis: Word
Machine.struct :CEntry, id: Word, value: Value, file: Ptr, file_len: Word, line: Word
Machine.sig :method, [Value, Word, Ptr, Value, Value] => Value
# Method kinds beyond a compiled def and a builtin: accessors keep the
# ivar's id in `fn`.
KIND_ATTR_READER = 3
KIND_ATTR_WRITER = 4
# A builtin that leaves no frame of its own: `Proc#call` and `send`,
# which CRuby keeps out of a backtrace.
KIND_FRAMELESS = 5
# An `undef`: the name answers nothing from here on down the chain.
KIND_UNDEF = 6

sig [Word, Value, Value] => Value
machine def zr_class_alloc(type, sup, klass)
  c = zr_alloc(type, klass)
  RClass.set_name(c, Machine.value(QNIL))
  RClass.set_superclass(c, sup)
  RClass.set_attached(c, Machine.value(QNIL))
  RClass.set_origin(c, Machine.value(QNIL))
  ext = malloc(ClassExt.size)
  ClassExt.set_mtab(ext, 0)
  ClassExt.set_mlen(ext, 0)
  ClassExt.set_mcap(ext, 0)
  ClassExt.set_ctab(ext, 0)
  ClassExt.set_clen(ext, 0)
  ClassExt.set_ccap(ext, 0)
  zr_ivtab_init(ClassExt.iv(ext))
  zr_ivtab_init(ClassExt.cv(ext))
  RClass.set_ext(c, ext)
  c
end

# A class without a metaclass yet: a builtin class gets one on first
# use, the way `zr_singleton_class` makes any.
sig [Value] => Value
machine def zr_class_boot(sup)
  zr_class_alloc(T_CLASS, sup, zr_global(G_CLASS))
end

# A class with its metaclass, as CRuby makes every class: the metaclass
# inherits from the superclass's, so class methods do too.
sig [Value] => Value
machine def zr_class_new(sup)
  c = zr_class_boot(sup)
  zr_make_metaclass(c)
  c
end

T_ICLASS = 28

# Whether `klass`'s chain holds `mod`, itself or as a proxy.
sig [Value, Value] => Bool
machine def zr_chain_includes(klass, mod)
  k = klass
  while k != QNIL
    if k == mod || (zr_type(k) == T_ICLASS && RClass.attached(k) == mod)
      return true
    end
    k = RClass.superclass(k)
  end
  false
end

# A proxy standing for `mod` in a chain, ahead of `sup`.
sig [Value, Value] => Value
machine def zr_iclass_new(mod, sup)
  ic = zr_alloc(T_ICLASS, mod)
  RClass.set_name(ic, Machine.value(QNIL))
  RClass.set_superclass(ic, sup)
  RClass.set_ext(ic, RClass.ext(mod))
  RClass.set_attached(ic, mod)
  RClass.set_origin(ic, Machine.value(QNIL))
  ic
end

# Where a class's own methods live: its origin proxy once something is
# prepended, else the class itself.
sig [Value] => Value
machine def zr_origin(klass)
  if RClass.origin(klass) != QNIL
    return RClass.origin(klass)
  end
  klass
end

# `include`: a proxy for `mod`, and for each module it includes, goes
# in right after `klass`'s origin, unless the chain holds it already.
sig [Value, Value] => Void
machine def zr_include_module(klass, mod)
  c = zr_origin(klass)
  m = mod
  while m != QNIL
    origin = zr_type(m) == T_ICLASS ? RClass.attached(m) : m
    unless zr_chain_includes(klass, origin)
      ic = zr_iclass_new(origin, RClass.superclass(c))
      RClass.set_superclass(c, ic)
      c = ic
    end
    m = RClass.superclass(m)
  end
end

# `prepend`: the class's methods move to an origin proxy under the
# prepended modules, whose proxies go in right after the class. The
# moved methods now belong to the origin, so their `super` starts
# below it.
sig [Value, Value] => Void
machine def zr_prepend_module(klass, mod)
  if RClass.origin(klass) == QNIL
    o = zr_iclass_new(klass, RClass.superclass(klass))
    ext = malloc(ClassExt.size)
    zr_memcpy(ext, RClass.ext(klass), ClassExt.size)
    ClassExt.set_ctab(ext, 0)
    ClassExt.set_clen(ext, 0)
    ClassExt.set_ccap(ext, 0)
    zr_ivtab_init(ClassExt.iv(ext))
    zr_ivtab_init(ClassExt.cv(ext))
    RClass.set_ext(o, ext)
    ClassExt.set_mtab(RClass.ext(klass), 0)
    ClassExt.set_mlen(RClass.ext(klass), 0)
    ClassExt.set_mcap(RClass.ext(klass), 0)
    i = 0
    while i < ClassExt.mlen(ext)
      e = ClassExt.mtab(ext) + (i * MEntry.size)
      if MEntry.meta(e) != 0 && FrameMeta.owner(MEntry.meta(e)) == klass
        FrameMeta.set_owner(MEntry.meta(e), o)
      end
      i += 1
    end
    RClass.set_superclass(klass, o)
    RClass.set_origin(klass, o)
  end
  c = klass
  m = mod
  while m != QNIL
    origin = zr_type(m) == T_ICLASS ? RClass.attached(m) : m
    unless zr_chain_includes(klass, origin)
      ic = zr_iclass_new(origin, RClass.superclass(c))
      RClass.set_superclass(c, ic)
      c = ic
    end
    m = RClass.superclass(m)
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_prepend(recv, argc, argv, cref, blk)
  i = argc - 1
  while i >= 0
    m = Machine.value(Machine.load64(argv + (i * 8), 0))
    r = zr_check_module(m)
    return r if r == QUNDEF
    zr_prepend_module(recv, m)
    r = zr_hook(m, Machine.id(:prepended), recv)
    return r if r == QUNDEF
    i -= 1
  end
  recv
end

# A hook such as `included` or `inherited`: `recv.mid(arg)`, private
# or not.
sig [Value, Word, Value] => Value
machine def zr_hook(recv, mid, arg)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(arg))
  zr_send(recv, mid, 1, slot)
end

sig [Value] => Value
machine def zr_check_module(m)
  if zr_special_p(m) || zr_type(m) != T_MODULE
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_str(b, zr_class_name_of(m))
    zr_buf_push(b, Machine.bytes(" (expected Module)"), 18)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.value(QNIL)
end

# `include`: each module, last first, then its `included` hook.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_include(recv, argc, argv, cref, blk)
  i = argc - 1
  while i >= 0
    m = Machine.value(Machine.load64(argv + (i * 8), 0))
    r = zr_check_module(m)
    return r if r == QUNDEF
    zr_include_module(recv, m)
    r = zr_hook(m, Machine.id(:included), recv)
    return r if r == QUNDEF
    i -= 1
  end
  recv
end

# `extend`: each module into the singleton class, then its `extended`
# hook.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_extend(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_wrong_arity_min(0, 1)
  end
  i = argc - 1
  while i >= 0
    m = Machine.value(Machine.load64(argv + (i * 8), 0))
    r = zr_check_module(m)
    return r if r == QUNDEF
    zr_include_module(zr_singleton_class(recv), m)
    r = zr_hook(m, Machine.id(:extended), recv)
    return r if r == QUNDEF
    i -= 1
  end
  recv
end

# `alias new old` and `alias_method`: the old entry again under the new
# name, keeping its meta, so a backtrace names the original.
sig [Value, Word, Word] => Value
machine def zr_alias(klass, new_id, old_id)
  e = zr_find_method(klass, old_id)
  if e == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, old_id)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_str(b, RClass.name(klass))
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_method_add_vis(klass, new_id, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), MEntry.meta(e), MEntry.cref(e), MEntry.vis(e))
  zr_method_added(klass, new_id)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_alias_method(recv, argc, argv, cref, blk)
  new_name = Machine.value(Machine.load64(argv, 0))
  old_name = Machine.value(Machine.load64(argv, 8))
  unless zr_symbol_p(new_name) && zr_symbol_p(old_name)
    zr_bug(Machine.bytes("alias_method with a String name is not implemented yet\n"), 55)
  end
  r = zr_alias(recv, zr_sym2id(new_name), zr_sym2id(old_name))
  return r if r == QUNDEF
  new_name
end

# `undef name`: an entry that stops the search, so the name is gone
# from this class and its subclasses even where an ancestor has it.
sig [Value, Word] => Value
machine def zr_undef(klass, id)
  if zr_find_method(klass, id) == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, id)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_str(b, RClass.name(klass))
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_method_add(klass, id, 0, 0, KIND_UNDEF, 0, Machine.value(QNIL))
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_undef_method(recv, argc, argv, cref, blk)
  i = 0
  while i < argc
    name = Machine.value(Machine.load64(argv + (i * 8), 0))
    unless zr_symbol_p(name)
      zr_bug(Machine.bytes("undef_method with a String name is not implemented yet\n"), 55)
    end
    r = zr_undef(recv, zr_sym2id(name))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

# `Module#===`: whether the object is one of the module's.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_eqq(recv, argc, argv, cref, blk)
  zr_bool(zr_is_a(Machine.value(Machine.load64(argv, 0)), recv))
end

# The class a class variable belongs to under `cref`: the innermost
# class, past a singleton class to what it is attached to. The
# toplevel has none, though a `class Object` body does.
sig [Value] => Value
machine def zr_cvar_base(cref)
  cref = zr_cref_lexical(cref)
  if cref == zr_global(G_TOP_CREF)
    return Machine.value(QNIL)
  end
  k = RCref.klass(cref)
  while zr_singleton_p(k)
    k = RClass.attached(k)
    if zr_special_p(k) || (zr_type(k) != T_CLASS && zr_type(k) != T_MODULE)
      return Machine.value(QNIL)
    end
  end
  k
end

# The class in `klass`'s chain whose table holds `id`, or nil.
sig [Value, Word] => Value
machine def zr_cvar_owner(klass, id)
  k = klass
  while k != QNIL
    if zr_ivtab_row(ClassExt.cv(RClass.ext(k)), id) != 0
      return k
    end
    k = RClass.superclass(k)
  end
  Machine.value(QNIL)
end

sig [Value, Word] => Value
machine def zr_cvar_get(cref, id)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  owner = zr_cvar_owner(base, id)
  if owner == QNIL
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("uninitialized class variable "), 29)
    zr_buf_sym(b, id)
    zr_buf_push(b, Machine.bytes(" in "), 4)
    zr_buf_str(b, RClass.name(base))
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  zr_ivtab_get(ClassExt.cv(RClass.ext(owner)), id)
end

# Whether `@@id` is set under `cref`.
sig [Value, Word] => Value
machine def zr_cvar_defined(cref, id)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  zr_bool(zr_cvar_owner(base, id) != QNIL)
end

sig [Value, Word, Value] => Value
machine def zr_cvar_set(cref, id, v)
  base = zr_cvar_base(cref)
  if base == QNIL
    return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("class variable access from toplevel"), 35)
  end
  owner = zr_cvar_owner(base, id)
  if owner == QNIL
    owner = base
  end
  zr_ivtab_set(ClassExt.cv(RClass.ext(owner)), id, v)
  v
end

# `Module#ancestors`: the chain, proxies as the modules they stand for.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_ancestors(recv, argc, argv, cref, blk)
  out = zr_ary_new(8)
  k = recv
  while k != QNIL
    if RClass.origin(k) == QNIL
      zr_ary_push(out, zr_type(k) == T_ICLASS ? RClass.attached(k) : k)
    end
    k = RClass.superclass(k)
  end
  out
end

# `Module#include?`: `mod` is in the chain, other than as itself.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_include_p(recv, argc, argv, cref, blk)
  m = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(m) || zr_type(m) != T_MODULE
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("wrong argument type Class (expected Module)"), 43)
  end
  zr_bool(m != recv && zr_chain_includes(recv, m))
end

sig [Value] => Bool
machine def zr_singleton_p(klass)
  (RBasic.flags(klass) & FL_SINGLETON) != 0
end

# The singleton class of the class `klass`: its superclass's, or Class
# for a root; `klass` itself has it as its class from here on.
sig [Value] => Value
machine def zr_make_metaclass(klass)
  sup = RClass.superclass(klass)
  while sup != QNIL && zr_type(sup) == T_ICLASS
    sup = RClass.superclass(sup)
  end
  if sup == QNIL
    msup = zr_global(G_CLASS)
  else
    msup = zr_singleton_class(sup)
  end
  meta = zr_class_alloc(T_CLASS, msup, zr_global(G_CLASS))
  RBasic.set_flags(meta, RBasic.flags(meta) | FL_SINGLETON)
  RClass.set_attached(meta, klass)
  RBasic.set_klass(klass, meta)
  meta
end

# The singleton class of `v`, made on first use. An Integer or a Symbol
# has none; nil, true and false answer their own class.
sig [Value] => Value
machine def zr_singleton_class(v)
  if zr_fixnum_p(v) || zr_symbol_p(v)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  if zr_special_p(v)
    return zr_class_of(v)
  end
  k = RBasic.klass(v)
  if zr_singleton_p(k) && RClass.attached(k) == v
    return k
  end
  if zr_type(v) == T_CLASS
    return zr_make_metaclass(v)
  end
  s = zr_class_alloc(T_CLASS, k, zr_global(G_CLASS))
  RBasic.set_flags(s, RBasic.flags(s) | FL_SINGLETON)
  RClass.set_attached(s, v)
  RBasic.set_klass(v, s)
  s
end

# The class `v.class` answers: past any singleton class.
# The class an object answers `class` with: past its singleton class
# and the proxies of the modules it extends.
sig [Value] => Value
machine def zr_real_class(v)
  k = zr_class_of(v)
  while zr_singleton_p(k) || zr_type(k) == T_ICLASS
    k = RClass.superclass(k)
  end
  k
end

sig [Value] => Value
machine def zr_class_name_of(v)
  RClass.name(zr_real_class(v))
end

sig [] => Value
machine def zr_module_new
  zr_class_alloc(T_MODULE, Machine.value(QNIL), zr_global(G_MODULE))
end

# The gate bit an operator's redefinition sets, or 0.
sig [Value, Word] => Word
machine def zr_gate_bit(klass, mid)
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
    else
      0
    end
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[])
    GATE_AREF
  elsif klass == zr_global(G_ARRAY) && mid == Machine.id(:[]=)
    GATE_ASET
  elsif (klass == zr_global(G_ARRAY) || klass == zr_global(G_STRING)) && mid == Machine.id(:<<)
    GATE_LTLT
  elsif mid == Machine.id(:!)
    GATE_NOT
  else
    0
  end
end

# A definition; the first one of each builtin operator is the runtime's
# own and leaves the gate clear, a later one sets it. `meta` is the
# compiled def's own FrameMeta, or 0 for a builtin, which gets one here.
sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_method(klass, mid, fn, arity, kind, meta, cref)
  zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, cref))
end

# `def obj.name`: a singleton def is public whatever its body's
# visibility verb says, except the initialize family.
sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Value
machine def zr_define_singleton_def(klass, mid, fn, arity, kind, meta, cref)
  zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, zr_definition_vis(mid, Machine.value(QNIL)))
end

sig [Value, Word, Ptr, Word, Word, Ptr, Value, Word] => Value
machine def zr_define_method_as(klass, mid, fn, arity, kind, meta, cref, vis)
  klass = zr_origin(klass)
  if meta == 0
    meta = malloc(FrameMeta.size)
    FrameMeta.set_file(meta, 0)
    FrameMeta.set_file_len(meta, 0)
    FrameMeta.set_kind(meta, KIND_BUILTIN)
    FrameMeta.set_line(meta, 0)
    FrameMeta.set_parent(meta, 0)
    FrameMeta.set_arity(meta, arity)
    FrameMeta.set_params(meta, 0)
    FrameMeta.set_fn(meta, 0)
  end
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  if cref != QNIL && RCref.modfn(cref) != 0
    zr_method_add_vis(zr_singleton_class(klass), mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
  end
  zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
  zr_method_added(klass, mid)
end

# The visibility a definition under `cref` gets: the body's current
# one, private under `module_function`, and always private for
# `initialize` and its kin.
sig [Word, Value] => Word
machine def zr_definition_vis(mid, cref)
  if mid == Machine.id(:initialize) || mid == Machine.id(:initialize_copy) || mid == Machine.id(:respond_to_missing?)
    return VIS_PRIVATE
  end
  if cref == QNIL
    return VIS_PUBLIC
  end
  if RCref.modfn(cref) != 0
    return VIS_PRIVATE
  end
  RCref.vis(cref)
end

# A method whose body is the Proc `body`, kept in the entry's cref
# slot; `cref` gives the visibility.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_define_bmethod(klass, mid, meta, body, cref)
  klass = zr_origin(klass)
  FrameMeta.set_name(meta, mid)
  FrameMeta.set_owner(meta, klass)
  zr_method_add_vis(klass, mid, 0, 0 - 1, KIND_BMETHOD, meta, body, zr_definition_vis(mid, cref))
  zr_method_added(klass, mid)
end

# The `method_added` hook, or `singleton_method_added` on the object
# a singleton class is attached to; nothing until the hooks exist.
sig [Value, Word] => Value
machine def zr_method_added(klass, mid)
  if zr_type(klass) == T_ICLASS
    klass = RClass.attached(klass)
  end
  if zr_singleton_p(klass)
    recv = RClass.attached(klass)
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

sig [Value, Word, Ptr, Word, Word, Ptr, Value] => Void
machine def zr_method_add(klass, mid, fn, arity, kind, meta, cref)
  zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, VIS_PUBLIC)
end

# The entry into the table, the meta as it is (an alias keeps the
# original's name).
sig [Value, Word, Ptr, Word, Word, Ptr, Value, Word] => Void
machine def zr_method_add_vis(klass, mid, fn, arity, kind, meta, cref, vis)
  klass = zr_origin(klass)
  if zr_find_method(klass, mid) != 0
    g = zr_gates()
    Machine.store64(g, 0, Machine.load64(g, 0) | zr_gate_bit(klass, mid))
  end
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  if n == ClassExt.mcap(ext)
    cap = n * 2
    if cap < 8
      cap = 8
    end
    tab = malloc(cap * MEntry.size)
    old = ClassExt.mtab(ext)
    if old != 0
      zr_memcpy(tab, old, n * MEntry.size)
      free(old)
    end
    ClassExt.set_mtab(ext, tab)
    ClassExt.set_mcap(ext, cap)
  end
  e = ClassExt.mtab(ext) + (n * MEntry.size)
  MEntry.set_mid(e, mid)
  MEntry.set_fn(e, fn)
  MEntry.set_arity(e, arity)
  MEntry.set_kind(e, kind)
  MEntry.set_meta(e, meta)
  MEntry.set_cref(e, cref)
  MEntry.set_vis(e, vis)
  ClassExt.set_mlen(ext, n + 1)
end

# `private`, `public`, `protected` and `module_function` as a class
# body's verbs: with no names they set what later defs get, through the
# caller's cref; with names they change those methods on `klass`.
sig [Value, Word, Ptr, Value, Word, Word] => Value
machine def zr_set_visibility(klass, argc, argv, blk, vis, modfn)
  if argc == 0
    cref = Frame.cref(Frame.prev(Task.top(zr_task())))
    if cref == QNIL
      zr_bug(Machine.bytes("a visibility verb outside a class body is not implemented yet\n"), 62)
    end
    if modfn != 0
      RCref.set_modfn(cref, 1)
    else
      RCref.set_vis(cref, vis)
      RCref.set_modfn(cref, 0)
    end
    return Machine.value(QNIL)
  end
  i = 0
  while i < argc
    name = Machine.value(Machine.load64(argv + (i * 8), 0))
    if !zr_special_p(name) && zr_type(name) == T_ARRAY
      r = zr_set_visibility(klass, RArray.len(name), RArray.ptr(name), blk, vis, modfn)
      return r if r == QUNDEF
    else
      unless zr_symbol_p(name)
        zr_bug(Machine.bytes("a visibility verb with a String name is not implemented yet\n"), 60)
      end
      r = zr_set_method_visibility(klass, zr_sym2id(name), vis, modfn)
      return r if r == QUNDEF
    end
    i += 1
  end
  if argc == 1
    return Machine.value(Machine.load64(argv, 0))
  end
  zr_ary_of(argc, argv)
end

sig [Value, Word, Word, Word] => Value
machine def zr_set_method_visibility(klass, mid, vis, modfn)
  e = zr_find_method(klass, mid)
  if e == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    zr_buf_sym(b, mid)
    zr_buf_push(b, zr_type(klass) == T_MODULE ? Machine.bytes("' for module '") : Machine.bytes("' for class '"), zr_type(klass) == T_MODULE ? 14 : 13)
    zr_buf_str(b, RClass.name(klass))
    zr_buf_byte(b, 39)
    return zr_raise_buf(zr_global(G_NAME_ERROR), b)
  end
  if modfn != 0
    zr_method_add_vis(zr_singleton_class(klass), mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), MEntry.meta(e), MEntry.cref(e), VIS_PUBLIC)
    vis = VIS_PRIVATE
  end
  if zr_find_method_at(zr_origin(klass), mid) == e
    MEntry.set_vis(e, vis)
  else
    zr_method_add_vis(zr_origin(klass), mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), MEntry.meta(e), MEntry.cref(e), vis)
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PUBLIC, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_protected(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PROTECTED, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_module_function(recv, argc, argv, cref, blk)
  zr_set_visibility(recv, argc, argv, blk, VIS_PRIVATE, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_class_method(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PRIVATE, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_class_method(recv, argc, argv, cref, blk)
  zr_set_visibility(zr_singleton_class(recv), argc, argv, blk, VIS_PUBLIC, 0)
end

# The names in one level's table, filtered by `vis` (a visibility, or
# -1 for all but private), into `out`. A name met at an earlier level
# is `seen` and decided there, an undef among them.
sig [Value, Value, Value, Word] => Void
machine def zr_level_method_names(level, out, seen, vis)
  ext = RClass.ext(level)
  i = 0
  while i < ClassExt.mlen(ext)
    e = ClassExt.mtab(ext) + (i * MEntry.size)
    name = zr_sym(MEntry.mid(e))
    if zr_ary_index_of(seen, name) < 0
      zr_ary_push(seen, name)
      if MEntry.kind(e) != KIND_UNDEF && (vis < 0 ? MEntry.vis(e) != VIS_PRIVATE : MEntry.vis(e) == vis)
        zr_ary_push(out, name)
      end
    end
    i += 1
  end
end

# `instance_methods` and the three by visibility, on a module (`all`
# for the ancestors too) or, for `methods` on an object, on its class
# chain: the singleton class and the modules it extends come first.
sig [Value, Word, Word, Bool] => Value
machine def zr_method_names(klass, all, vis, object)
  out = zr_ary_new(8)
  seen = zr_ary_new(8)
  k = all == 0 ? zr_origin(klass) : klass
  if object
    while k != QNIL && (zr_singleton_p(k) || zr_type(k) == T_ICLASS)
      zr_level_method_names(k, out, seen, vis)
      k = RClass.superclass(k)
    end
  end
  while k != QNIL
    zr_level_method_names(k, out, seen, vis)
    if all == 0 && zr_type(k) != T_ICLASS
      k = Machine.value(QNIL)
    else
      k = RClass.superclass(k)
    end
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, 0 - 1, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_public_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PUBLIC, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_private_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PRIVATE, false)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_protected_instance_methods(recv, argc, argv, cref, blk)
  all = argc == 0 || (Machine.value(Machine.load64(argv, 0)) != QFALSE && Machine.value(Machine.load64(argv, 0)) != QNIL)
  zr_method_names(recv, all ? 1 : 0, VIS_PROTECTED, false)
end

sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin(klass, mid, fn, arity)
  zr_define_method(klass, mid, fn, arity, KIND_BUILTIN, 0, Machine.value(QNIL))
end

# A builtin that is private, as Kernel's `puts` and `raise` are.
sig [Value, Word, Ptr, Word] => Void
machine def zr_builtin_private(klass, mid, fn, arity)
  zr_builtin(klass, mid, fn, arity)
  MEntry.set_vis(zr_find_method_at(zr_origin(klass), mid), VIS_PRIVATE)
end

# The entry for `mid` on `klass` alone, or 0; the last definition wins.
sig [Value, Word] => Ptr
machine def zr_find_method_at(klass, mid)
  ext = RClass.ext(klass)
  n = ClassExt.mlen(ext)
  tab = ClassExt.mtab(ext)
  i = n - 1
  while i >= 0
    e = tab + (i * MEntry.size)
    if MEntry.mid(e) == mid
      return e
    end
    i -= 1
  end
  0
end

# The entry for `mid` on `klass` or an ancestor, or 0; an undef on the
# way is 0 too.
sig [Value, Word] => Ptr
machine def zr_find_method(klass, mid)
  while klass != QNIL
    e = zr_find_method_at(klass, mid)
    if e != 0
      if MEntry.kind(e) == KIND_UNDEF
        return 0
      end
      return e
    end
    klass = RClass.superclass(klass)
  end
  0
end

sig [Value] => Value
machine def zr_class_of(v)
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
  else
    RBasic.klass(v)
  end
end

# Whether `klass` is `target` or inherits from it, or includes it.
sig [Value, Value] => Bool
machine def zr_class_inherits(klass, target)
  zr_chain_includes(klass, target)
end

sig [Value, Value] => Bool
machine def zr_is_a(v, klass)
  zr_class_inherits(zr_class_of(v), klass)
end

# A method table's crefs, and the Procs of the methods a block made.
sig [Ptr] => Void
machine def zr_mark_mtab(ext)
  n = ClassExt.mlen(ext)
  i = 0
  while i < n
    zr_mark(MEntry.cref(ClassExt.mtab(ext) + (i * MEntry.size)))
    i += 1
  end
end

# What a cell holds besides its class: marked by type.
sig [Value] => Void
machine def zr_mark_children(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_ICLASS
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
    if RClass.origin(RClass.attached(v)) == v
      zr_mark_mtab(RClass.ext(v))
    end
  elsif t == T_CLASS || t == T_MODULE
    zr_mark(RClass.name(v))
    zr_mark(RClass.superclass(v))
    zr_mark(RClass.attached(v))
    ext = RClass.ext(v)
    zr_mark_mtab(ext)
    n = ClassExt.clen(ext)
    i = 0
    while i < n
      zr_mark(CEntry.value(ClassExt.ctab(ext) + (i * CEntry.size)))
      i += 1
    end
    zr_mark_ivtab(ClassExt.iv(ext))
    zr_mark_ivtab(ClassExt.cv(ext))
  elsif t == T_EXCEPTION
    zr_mark(RException.message(v))
  elsif t == T_OBJECT
    zr_mark_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    zr_mark_ary(v)
  elsif t == T_HASH
    zr_mark_hash(v)
  elsif t == T_CREF
    zr_mark(RCref.klass(v))
    zr_mark(RCref.next(v))
  elsif t == T_ENV
    zr_mark_env(v)
  elsif t == T_PROC
    zr_mark_proc(v)
  elsif t == T_METHOD
    zr_mark_method(v)
  end
end

# What a cell owns outside the arena: freed with it.
sig [Value] => Void
machine def zr_release(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_ICLASS
    if RClass.origin(RClass.attached(v)) == v
      if ClassExt.mtab(RClass.ext(v)) != 0
        free(ClassExt.mtab(RClass.ext(v)))
      end
      free(RClass.ext(v))
    end
  elsif t == T_CLASS || t == T_MODULE
    ext = RClass.ext(v)
    if ClassExt.mtab(ext) != 0
      free(ClassExt.mtab(ext))
    end
    if ClassExt.ctab(ext) != 0
      free(ClassExt.ctab(ext))
    end
    zr_release_ivtab(ClassExt.iv(ext))
    zr_release_ivtab(ClassExt.cv(ext))
    free(ext)
  elsif t == T_STRING
    if RString.ptr(v) != 0
      free(RString.ptr(v))
    end
  elsif t == T_EXCEPTION
    if RException.rows(v) != 0
      free(RException.rows(v))
    end
  elsif t == T_OBJECT
    zr_release_ivtab(RObject.iv(v))
  elsif t == T_ARRAY
    free(RArray.ptr(v))
  elsif t == T_HASH
    if RHash.entries(v) != 0
      free(RHash.entries(v))
    end
  elsif t == T_ENV
    free(REnv.slots(v))
  end
end
